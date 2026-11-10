require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (eval com provedor pago só com execução explícita e teto).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto da rodada em `AUTONOMIA_EVAL_TETO_USD` (padrão 0,50): passou,
# a rodada para no meio e falha dizendo o gasto.
#
# #2858 F3: quais ferramentas prontas combinam com um agente é leitura do MODELO, sem lista de palavras. Só se prova com
# o modelo, nos dois caminhos da produção:
# - o Construtor, no fechamento da criação (mesma instrução-mãe, mesmo input montado pelo Builder com as prontas
#   liberadas, mesmo schema e mesmo esforço de raciocínio);
# - a sugestão para um agente que já existe (`SugestaoParaAgente`, modelo barato).
# Seis agentes de seguro e um caso negativo (a padaria). A régua é fechada: o que o agente PRECISA ter e o que ele SÓ
# PODE ter (fonte a mais reprova, tanto quanto fonte a menos). Conversas inventadas, sem dado de cliente.
module AvaliacaoDasProntas
  ABERTURA = 'Oi! Vamos montar seu agente. Me conta o que ele vai fazer e para quem.'.freeze
  FECHAR = 'Pode fechar assim mesmo.'.freeze

  # [nome, o que o dono contou, precisa ter, só pode ter (nil = qualquer outra além das que precisa)]
  CASOS = [
    ['Ana', 'Sou corretora. Quero a Ana cotando seguro auto: ela pede o modelo e o ano do carro e o CEP de onde ele dorme.',
     %w[fipe], nil],
    ['Beto', 'O Beto vai cotar seguro residencial: pergunta o endereço do imóvel pelo CEP e o tipo de casa.',
     %w[cep], %w[cep]],
    ['Carla', 'A Carla atende empresas que querem seguro empresarial. Ela confere os dados da empresa pelo CNPJ.',
     %w[cnpj], %w[cnpj]],
    ['Davi', 'O Davi tira dúvidas sobre seguro de vida: coberturas, carência e como incluir beneficiários.',
     %w[], %w[]],
    ['Eva', 'A Eva vende seguro viagem internacional e explica quanto custa a cobertura em dólar.',
     %w[], %w[]],
    ['Fabio', 'O Fabio cota seguro de frota para transportadoras: confere a empresa pelo CNPJ e o valor dos caminhões.',
     %w[fipe cnpj], %w[fipe cnpj]],
    ['Gina', 'A Gina atende a padaria do bairro: fala o cardápio do dia, os preços dos pães e o horário de abrir.',
     %w[], %w[]]
  ].freeze
end

RSpec.describe 'Ferramentas prontas escolhidas pelo modelo' do # rubocop:disable RSpec/DescribeClass
  include FerramentasProntasHelper

  around do |example|
    WebMock.allow_net_connect!
    example.run
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  let(:account) { create(:account) }
  let(:teto) { ENV.fetch('AUTONOMIA_EVAL_TETO_USD', '0.50').to_f }
  let(:gasto) { { usd: 0.0 } }
  let(:credencial) { { api_key: ENV.fetch('OPENAI_API_KEY', nil) } }

  before do
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::FLAG_VITRINE, Autonomia::FerramentasProntas::FLAG_CONSTRUTOR)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(instance_double(Crm::Ai::CredentialResolver, resolve: credencial))
    allow_any_instance_of(Crm::Ai::ResponsesClient).to receive(:create).and_wrap_original do |original, **kwargs| # rubocop:disable RSpec/AnyInstance
      raise "teto de US$ #{teto} atingido (gasto US$ #{gasto[:usd].round(4)})" if gasto[:usd] >= teto

      original.call(**kwargs).tap do |raw|
        gasto[:usd] += Crm::Ai::UsageRecorder.cost_for(kwargs[:model], Crm::Ai::UsageRecorder.extract_tokens(raw[:usage]))
      end
    end
  end

  def do_construtor(nome, conta)
    thread = Autonomia::Agents::BuildThread.create!(account: account)
    thread.persist_start_options!(type: 'custom', with_knowledge: false)
    thread.save!
    thread.append_message!('assistant', AvaliacaoDasProntas::ABERTURA)
    thread.append_message!('user', conta)
    thread.append_message!('user', AvaliacaoDasProntas::FECHAR)
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread)
    raw = Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'eval_construtor').create(
      model: Autonomia::Agents::Config::BUILDER_MODEL, instructions: Autonomia::Agents::Builder::MOTHER_INSTRUCTION,
      input: builder.send(:build_input), schema: Autonomia::Agents::Builder::BUILDER_SCHEMA,
      reasoning_effort: Autonomia::Agents::Config::BUILDER_REASONING_EFFORT
    )
    escolha = Autonomia::Agents::Builder::ProntasSugeridas.filtrar(account, JSON.parse(raw[:text]))
    [nome, escolha]
  end

  def da_sugestao(nome, conta)
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'sdr', instruction: "Você é #{nome}. #{conta}")
    [nome, Autonomia::FerramentasProntas::SugestaoParaAgente.new(agente).call]
  end

  def erros(caminho)
    AvaliacaoDasProntas::CASOS.filter_map do |nome, conta, precisa, so_pode|
      _, escolha = send(caminho, nome, conta)
      puts "[eval prontas] #{caminho} #{nome}: #{escolha.inspect}"
      faltou = precisa - Array(escolha)
      sobrou = so_pode.nil? ? [] : Array(escolha) - so_pode
      "#{caminho} #{nome}: escolheu #{escolha.inspect} (faltou #{faltou}, a mais #{sobrou})" if escolha.nil? || faltou.any? || sobrou.any?
    end
  end

  # `AUTONOMIA_EVAL_CAMINHO=construtor` (ou `sugestao`) roda só um dos dois caminhos.
  def caminhos
    { 'construtor' => %i[do_construtor], 'sugestao' => %i[da_sugestao] }.fetch(ENV.fetch('AUTONOMIA_EVAL_CAMINHO', ''), %i[do_construtor da_sugestao])
  end

  it 'o Construtor e a sugestão escolhem as prontas que combinam com o agente, e a padaria fica sem', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    falhas = caminhos.flat_map { |caminho| erros(caminho) }
    puts "[eval prontas] #{AvaliacaoDasProntas::CASOS.size * caminhos.size} chamadas, gasto US$ #{gasto[:usd].round(4)}"

    expect(falhas).to be_empty, "escolhas erradas:\n#{falhas.join("\n")}"
  end
end

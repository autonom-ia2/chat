require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (eval com provedor pago só com execução explícita e teto).
# Roda com `AUTONOMIA_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto da rodada em `AUTONOMIA_EVAL_TETO_USD` (padrão 0,50): passou,
# a rodada para no meio e falha dizendo o gasto.
#
# #2858 F3: quais ferramentas prontas combinam com um agente é leitura do MODELO, sem lista de palavras. Só se prova com
# o modelo, nos dois caminhos da produção:
# - o Construtor, no fechamento da criação (mesma instrução-mãe, mesmo input montado pelo Builder com as prontas
#   liberadas, mesmo schema e mesmo esforço de raciocínio): as 4 primeiras são o "já vem com", as seguintes o "também
#   combina";
# - a sugestão para um agente que já existe (`SugestaoParaAgente`, modelo barato).
# A régua é a tabela "O que cada agente de seguro precisa ganhar no Construtor" do plano (#2858), só com as fontes
# que já existem (F1), e o caso negativo da padaria. O que o dono conta é o roteiro do vídeo do protótipo (j6-construtor).
# Passa quem recebe tudo o que PRECISA no "já vem com" ou no "também combina" (a um toque na Confira) e nada do que NÃO
# PODE, como diz o plano (decisões do Rodrigo, 10/11: régua inteira, 7 de 7, o mais completo dentro da regra QI 70). O que
# vier além da régua é impresso para leitura, sem reprovar: a Confira deixa tirar. Conversas inventadas, sem dado de
# cliente. `AUTONOMIA_EVAL_CASOS=Rita,Gina` roda só esses agentes.
module AvaliacaoDasProntas
  ABERTURA = 'Oi! Vamos montar seu agente. Me conta o que ele vai fazer e para quem.'.freeze
  PERGUNTA = 'Como ele vai falar com os clientes?'.freeze
  FECHAR = 'Pode fechar assim mesmo.'.freeze

  # [nome, o que o dono contou, como ele fala, precisa, não pode, aceitas (relação direta com o que foi contado)]
  CASOS = [
    ['Gael', 'Atender empresas que precisam de seguro garantia para licitação e contrato com o governo.',
     'Formal, mas simpático. Ele se chama Gael.', %w[cnpj feriados], %w[fipe], %w[]],
    ['Ana', 'Atender quem quer seguro de carro: tirar dúvidas e já começar a cotação.',
     'Simpática e direta. Ela se chama Ana.', %w[fipe cep cpf], %w[], %w[]],
    ['Rita', 'Cuidar do seguro residencial: cotação, dúvidas de cobertura e primeiro atendimento de sinistro.',
     'Acolhedora e calma. Ela se chama Rita.', %w[cep banco_central], %w[], %w[]],
    # Carga: as cidades de origem e destino da viagem têm relação com o seguro de cada viagem.
    ['Caio', 'Atender transportadoras que precisam de seguro de carga para cada viagem.',
     'Prático e rápido. Ele se chama Caio.', %w[cnpj], %w[], %w[cep cidades]],
    ['Lívia', 'Atender clientes de plano de saúde e seguro de vida: cobertura de exames, hospitais e doenças.',
     'Cuidadosa e clara. Ela se chama Lívia.', %w[], %w[fipe], %w[]],
    ['Sol', 'Vender seguro para quem tem placas solares em casa ou na empresa.',
     'Animado e direto. Ele se chama Sol.', %w[cep], %w[], %w[]],
    ['Gina', 'A Gina atende a padaria do bairro: fala o cardápio do dia, os preços dos pães e o horário de abrir.',
     'Simpática. Ela se chama Gina.', %w[], %w[fipe cpf cnpj bancos], %w[]]
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

  def do_construtor(caso)
    _, conta, jeito = caso
    thread = Autonomia::Agents::BuildThread.create!(account: account)
    thread.persist_start_options!(type: 'custom', with_knowledge: false)
    thread.save!
    thread.append_message!('assistant', AvaliacaoDasProntas::ABERTURA)
    thread.append_message!('user', conta)
    thread.append_message!('assistant', AvaliacaoDasProntas::PERGUNTA)
    thread.append_message!('user', "#{jeito} #{AvaliacaoDasProntas::FECHAR}")
    builder = Autonomia::Agents::Builder.new(account: account, build_thread: thread)
    raw = Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'eval_construtor').create(
      model: Autonomia::Agents::Config::BUILDER_MODEL, instructions: Autonomia::Agents::Builder::MOTHER_INSTRUCTION,
      input: builder.send(:build_input), schema: Autonomia::Agents::Builder::BUILDER_SCHEMA,
      reasoning_effort: Autonomia::Agents::Config::BUILDER_REASONING_EFFORT
    )
    Autonomia::Agents::Builder::ProntasSugeridas.dividir(account, JSON.parse(raw[:text]))
  end

  def da_sugestao(caso)
    nome, conta, = caso
    agente = Autonomia::Agents::Agent.create!(account: account, name: nome, agent_type: 'sdr', instruction: "Você é #{nome}. #{conta}")
    chaves = Autonomia::FerramentasProntas::SugestaoParaAgente.new(agente).call || []
    maximo = Autonomia::Agents::Builder::ProntasSugeridas::MAXIMO
    { sugeridas: chaves.first(maximo), tambem: chaves.drop(maximo) }
  end

  def erros(caminho)
    casos.filter_map do |caso|
      nome, _, _, precisa, nao_pode, aceitas = caso
      escolha = send(caminho, caso)
      ja_vem = escolha[:sugeridas]
      todas = ja_vem + escolha[:tambem]
      puts "[eval prontas] #{caminho} #{nome}: já vem #{ja_vem.inspect}, também combina #{escolha[:tambem].inspect}"
      faltou = precisa - todas
      proibida = todas & nao_pode
      extras = todas - precisa - aceitas
      puts "[eval prontas] #{caminho} #{nome}: além da régua #{extras.inspect}" if extras.any?
      next if faltou.empty? && proibida.empty?

      "#{caminho} #{nome}: #{todas.inspect} (faltou #{faltou}, não pode #{proibida})"
    end
  end

  def casos
    nomes = ENV.fetch('AUTONOMIA_EVAL_CASOS', '').split(',').map(&:strip).compact_blank
    nomes.empty? ? AvaliacaoDasProntas::CASOS : AvaliacaoDasProntas::CASOS.select { |caso| nomes.include?(caso.first) }
  end

  # `AUTONOMIA_EVAL_CAMINHO=construtor` (ou `sugestao`) roda só um dos dois caminhos.
  def caminhos
    { 'construtor' => %i[do_construtor], 'sugestao' => %i[da_sugestao] }.fetch(ENV.fetch('AUTONOMIA_EVAL_CAMINHO', ''), %i[do_construtor da_sugestao])
  end

  it 'o Construtor e a sugestão escolhem as prontas que combinam com o agente, e a padaria fica sem', :eval_pago do
    ligada = ENV['AUTONOMIA_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?
    skip 'avaliação paga: rode com AUTONOMIA_EVAL_PAGO=1 e OPENAI_API_KEY' unless ligada

    falhas = caminhos.flat_map { |caminho| erros(caminho) }
    puts "[eval prontas] #{casos.size * caminhos.size} chamadas, gasto US$ #{gasto[:usd].round(4)}"

    expect(falhas).to be_empty, "escolhas erradas:\n#{falhas.join("\n")}"
  end
end

require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto do #1924: US$ 0,30 para as duas rodadas (antes e depois); esta
# rodada para ao passar de US$ 0,15, somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1924: a IA de assunto separa venda de pós-venda. Três ramos de negócio inventados, cada um com um funil de venda
# (com uma etapa de implantação/entrega depois da venda) e um de atendimento a quem já é cliente. Os textos de "quando
# usar" são de propósito curtos e genéricos: o que se mede é o tipo do funil, a janela de mensagens e o texto neutro das
# opções, não um "quando usar" caprichado. Casos:
#   - fica: dúvida de quem está na implantação do funil de venda é do card aberto; nenhum card nasce;
#   - atendimento: cancelamento ou renovação de quem já é cliente vai ao funil de atendimento (um deles com o pedido
#     feito antes das 5 últimas mensagens e a última mensagem continuando o pedido, outro com o card atual sem nome no
#     funil de venda);
#   - venda (controle): quem está num card de atendimento e quer comprar outra coisa vai ao funil de venda.
# O modelo maior é REAL (Crm::Subjects::Reviewer). O Jev é simulado com certeza zero ("não sei"), para que quem decide
# seja o modelo maior; o tamanho do que iria ao Jev é medido pelo corpo da chamada simulada. Dados fictícios; nenhum
# prompt é gravado. A saída (resposta, ação, tokens, custo) vai para EVAL_SAIDA (JSON).
module VendaPosVendaEval
  TETO_USD = 0.15

  RAMOS = {
    seguro: {
      a: ['Seguros', 'Pessoas interessadas em contratar seguro.', ['Novo lead', 'Cotação enviada', 'Implantação', 'Perdido']],
      b: ['Atendimento', 'Suporte aos clientes.', ['Triagem', 'Em andamento', 'Resolvido']]
    },
    software: {
      a: ['Comercial', 'Empresas interessadas no sistema de gestão.', ['Novo lead', 'Demonstração', 'Implantação', 'Perdido']],
      b: ['Sucesso do cliente', 'Suporte aos clientes.', ['Aberto', 'Em análise', 'Concluído']]
    },
    academia: {
      a: ['Matrículas', 'Quem quer conhecer os planos da academia.', ['Interessado', 'Aula experimental', 'Implantação', 'Perdido']],
      b: ['Relacionamento', 'Suporte aos alunos.', ['Novo', 'Em tratamento', 'Resolvido']]
    }
  }.freeze

  # [ramo, categoria, card aberto, mensagens (c: cliente, e: equipe), funil esperado para pedido novo]
  # card aberto: [funil, nome do card ou nil (sem nome: o nome do contato), etapa]
  CASOS = [
    [:seguro, :fica, [:a, 'Seguro do Corolla', 'Implantação'],
     [[:e, 'Apólice emitida! Bem-vindo. Nos próximos dias chega o kit com o cartão do seguro.'],
      [:c, 'Que bom! O cartão chega pelo correio ou por e-mail? E a vistoria do carro ainda precisa ser feita?']]],
    [:seguro, :atendimento, [:a, 'Seguro do Onix', 'Implantação'],
     [[:c, 'Quero cancelar o seguro do meu carro, vendi o Onix semana passada'], [:e, 'Entendi. Qual a data da venda?'],
      [:c, 'Dia 12'], [:e, 'O comprador já transferiu o documento?'], [:c, 'Sim, já está no nome dele'],
      [:e, 'Certo, vou verificar aqui'], [:c, 'Consegue resolver ainda hoje?']], :b],
    [:seguro, :atendimento, [:a, nil, 'Novo lead'],
     [[:c, 'Oi, meu seguro residencial com vocês vence mês que vem. Quero renovar, como faço?']], :b],
    [:seguro, :venda, [:b, 'Segunda via do boleto', 'Em andamento'],
     [[:e, 'Pronto, a segunda via do boleto foi para o seu e-mail.'],
      [:c, 'Obrigado! Aproveitando, queria fazer um seguro para a moto que acabei de comprar']], :a],

    [:software, :fica, [:a, 'Sistema para a loja', 'Implantação'],
     [[:e, 'Contrato assinado! Agora começa a implantação: a consultora vai configurar o sistema com vocês.'],
      [:c, 'Ótimo. Como importo a planilha de produtos que já temos? E quantos usuários posso cadastrar?']]],
    [:software, :atendimento, [:a, 'Sistema para a loja', 'Implantação'],
     [[:c, 'Queremos cancelar a assinatura do sistema a partir do mês que vem'], [:e, 'Poxa, posso perguntar o motivo?'],
      [:c, 'Vamos fechar uma das lojas'], [:e, 'Entendo. Vocês usam quantas licenças hoje?'], [:c, 'Cinco'],
      [:e, 'Ok, vou ver as condições do contrato'], [:c, 'Tem multa por sair antes do fim do contrato?']], :b],
    [:software, :atendimento, [:a, nil, 'Novo lead'],
     [[:c, 'Bom dia, somos clientes há um ano e o contrato vence agora. Queremos renovar por mais 12 meses.']], :b],
    [:software, :venda, [:b, 'Erro na nota fiscal', 'Em análise'],
     [[:e, 'O erro da nota fiscal foi corrigido na versão de hoje.'],
      [:c, 'Show, funcionou. Outra coisa: queremos contratar o sistema também para a nossa nova filial em outra cidade']], :a],

    [:academia, :fica, [:a, 'Plano anual', 'Implantação'],
     [[:e, 'Matrícula feita! Na primeira semana você faz a avaliação física e monta o treino com o professor.'],
      [:c, 'Legal! Preciso levar alguma coisa na avaliação física? E qual horário tem professor livre?']]],
    [:academia, :atendimento, [:a, 'Plano mensal', 'Implantação'],
     [[:c, 'Quero cancelar meu plano, vou me mudar de cidade'], [:e, 'Que pena! Quando é a mudança?'],
      [:c, 'Dia 30'], [:e, 'Você tem alguma pendência de pagamento?'], [:c, 'Não, está tudo pago'],
      [:e, 'Certo, vou consultar aqui'], [:c, 'Dá para encerrar ainda esta semana?']], :b],
    [:academia, :atendimento, [:a, nil, 'Interessado'],
     [[:c, 'Oi! Sou aluna, meu plano semestral termina semana que vem e quero renovar por mais seis meses']], :b],
    [:academia, :venda, [:b, 'Catraca não libera', 'Em tratamento'],
     [[:e, 'Liberamos sua digital na catraca, pode testar.'],
      [:c, 'Funcionou, valeu! E queria matricular a minha filha também, quais planos vocês têm para adolescente?']], :a]
  ].freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1924: a IA de assunto separa venda de pós-venda' do
  let(:account) { create(:account, name: 'Empresa Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  # A resposta do modelo maior e o tamanho do que iria ao Jev, do caso que está rodando.
  let(:registro) { {} }
  let(:ramos) { {} }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    allow(Crm::Ai::Config).to receive(:media_enabled?).and_return(false)
    allow(TypesafeAi::Config).to receive_messages(configured?: true, api_key: 'ts_eval_not_real', model: 'jev-1.13.0')
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    account.enable_features!(Crm::Conversations::CardEmFoco::FLAG)
    stub_jev
    guardar_resposta
  end

  # Um ramo, uma caixa, dois funis ligados a ela: o de venda e o de atendimento.
  def ramo(chave)
    ramos[chave] ||= begin
      inbox = create(:inbox, account: account, name: "Caixa #{chave}")
      account.crm_inbox_settings.create!(inbox: inbox, crm_enabled: true, auto_create_card: false, subject_ai_mode: :auto)
      funis = VendaPosVendaEval::RAMOS.fetch(chave).to_h do |letra, (nome, quando, etapas)|
        [letra, funil(inbox, nome, quando, etapas, venda: letra == :a)]
      end
      { inbox: inbox, funis: funis }
    end
  end

  def funil(inbox, nome, quando, etapas, venda:)
    pipeline, primeira = create_crm_pipeline(account: account, user: admin, name: nome)
    pipeline.update!(when_to_use: quando, counts_as_sale: venda)
    primeira.update!(name: etapas.first)
    etapas.drop(1).each_with_index { |etapa, posicao| create_crm_stage(account: account, pipeline: pipeline, name: etapa, position: posicao + 1) }
    account.crm_pipeline_inboxes.create!(pipeline: pipeline, inbox: inbox, default_stage: primeira, auto_create_card: false, created_by: admin)
    pipeline
  end

  def guardar_resposta
    allow(Crm::Subjects::Reviewer).to receive(:new).and_wrap_original do |original, *args|
      original.call(*args).tap do |revisor|
        allow(revisor).to receive(:revisar).and_wrap_original do |revisar, *dados|
          revisar.call(*dados).tap { |veredito| registro[:resposta] = veredito.resposta }
        end
      end
    end
  end

  # O Jev "não sabe" (certeza zero): o modelo maior decide sempre. Guarda o tamanho do que iria ao Jev.
  def stub_jev
    stub_request(:post, 'https://api.typesafe.ai/v1/systemone').to_return do |request|
      registro[:jev_chars] = request.body.to_s.length
      { status: 200,
        body: { model: 'jev-1.13.0', usage: { input_tokens: 0, output_tokens: 0 },
                answers: { decisao: { type: 'choice', choice: Crm::Subjects::Question::SEM_ASSUNTO, confidence: 0.0 } } }.to_json }
    end
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0, tokens_in: 0, tokens_out: 0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1924-venda-pos-venda.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = lambda do |*, payload|
      saida[:custo_usd] += payload[:cost].to_f
      next unless payload[:feature] == Crm::Subjects::FEATURE_REVISAO

      saida[:tokens_in] += payload.dig(:tokens, :in).to_i
      saida[:tokens_out] += payload.dig(:tokens, :out).to_i
    end
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > VendaPosVendaEval::TETO_USD

    resultado
  end

  def montar(indice, chave, (funil, nome, etapa), mensagens)
    dados = ramo(chave)
    contato = create(:contact, account: account, name: "Pessoa Teste #{indice}")
    conversa = create(:conversation, account: account, inbox: dados[:inbox], contact: contato)
    ultima = mensagens.map do |(quem, texto)|
      create(:message, account: account, inbox: dados[:inbox], conversation: conversa, content: texto,
                       message_type: quem == :c ? :incoming : :outgoing)
    end.last
    [conversa, ultima, card_aberto(conversa, dados, funil, nome, etapa)]
  end

  def card_aberto(conversa, dados, funil, nome, etapa)
    pipeline = dados[:funis].fetch(funil)
    stage = pipeline.stages.find_by!(name: etapa)
    metadata = nome ? { 'subject' => { 'source' => 'ai' } } : {}
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: conversa.contact, primary_conversation: conversa,
                                     inbox: dados[:inbox], title: nome || conversa.contact.name, metadata: metadata)
    Crm::CardConversation.find_or_create_by!(account: account, card: card, conversation: conversa)
                         .update!(is_primary: true, focused_at: 1.hour.ago)
    card
  end

  def rodar(indice, (chave, categoria, card, mensagens, esperado))
    conversa, mensagem, aberto = montar(indice, chave, card, mensagens)
    antes = account.crm_cards.pluck(:id)
    registro.clear
    decisao = com_custo { Crm::Subjects::Identifier.new(conversation: conversa, message: mensagem).perform }
    novos = account.crm_cards.where.not(id: antes)
    saida[:casos] << { indice: indice, ramo: chave, categoria: categoria, card_sem_nome: card[1].nil?, mensagens: mensagens.size,
                       cards_novos: novos.count, novo_no_funil_esperado: no_funil?(novos, chave, esperado), **resultado(aberto, decisao) }
  end

  def no_funil?(novos, chave, esperado)
    esperado && novos.exists?(pipeline_id: ramo(chave)[:funis].fetch(esperado).id)
  end

  def resultado(aberto, decisao)
    { resposta: registro[:resposta], sobre_o_card: [Crm::Subjects::Question::MESMO_ASSUNTO, "card_#{aberto.id}"].include?(registro[:resposta]),
      estado: decisao&.state, acao: decisao&.action, jev_chars: registro[:jev_chars], titulo: decisao&.title, motivo: decisao&.reason }
  end

  def certo?(caso)
    case caso[:categoria]
    when :fica then caso[:sobre_o_card] && caso[:cards_novos].zero?
    else caso[:novo_no_funil_esperado]
    end
  end

  it '12 conversas fictícias em 3 ramos: venda e pós-venda no funil certo' do
    VendaPosVendaEval::CASOS.each_with_index { |caso, indice| rodar(indice, caso) }
    saida[:casos].each { |caso| caso[:certo] = certo?(caso) }
    saida[:placar] = saida[:casos].group_by { |caso| caso[:ramo] }
                                  .transform_values { |casos| "#{casos.count { |caso| caso[:certo] }}/#{casos.size}" }
    saida[:placar_categoria] = saida[:casos].group_by { |caso| caso[:categoria] }
                                            .transform_values { |casos| "#{casos.count { |caso| caso[:certo] }}/#{casos.size}" }
    gravar_saida!

    errados = saida[:casos].reject { |caso| caso[:certo] }
    expect(errados.select { |caso| caso[:categoria] == :fica }).to be_empty
    expect(errados.size).to be <= 1
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass

require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 0,30 (#1922): a rodada para ao passar dele, somado pelo
# evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1922: a IA de etapa REAL (Crm::Ai::Evaluator, gatilho de mensagem, movimento automático ligado) avalia cards de lixo
# e cards de negócio de quatro ramos fictícios. Cada caso roda duas vezes: ANTES (o prompt e o schema sem a regra "não é
# negócio", como na base) e DEPOIS (com ela). Critérios (hard, só no DEPOIS): nenhum card de negócio arquivado, a perda
# declarada vai para a etapa de perda (não para "não é negócio"), e pelo menos 6 dos 7 cards de lixo arquivados. As
# saídas vão para EVAL_SAIDA (JSON). Conversas inventadas; nenhum prompt é gravado.
module NaoENegocioEval
  TETO_USD = 0.30
  MINIMO_LIXO = 6

  ETAPAS = [
    ['Novo', 'Primeiro contato, ainda sem pedido claro.'],
    ['Em atendimento', 'O cliente disse o que quer e estamos entendendo o pedido.'],
    ['Proposta enviada', 'Já mandamos orçamento, proposta ou cotação.'],
    ['Ganho', 'O cliente fechou com a gente.'],
    ['Perdido', 'O cliente desistiu, recusou ou fechou com outro.']
  ].freeze

  # [nome, ramo, esperado (:lixo, :negocio ou :perda), mensagens [quem, texto, horas atrás]]. quem: :cliente, :nos.
  CASOS = [
    ['fornecedor_oferece_leads', 'Corretora de seguros', :lixo, [
      [:cliente, 'Bom dia! Sou da LeadMax, geramos leads qualificados de seguro auto para corretoras. ' \
                 'Posso apresentar nosso pacote com 200 leads por mês?', 30],
      [:nos, 'Olá! Como posso ajudar?', 30]
    ]],
    ['engano_pessoa_errada', 'Clínica odontológica', :lixo, [
      [:cliente, 'Amor, passa no mercado e compra pão e leite', 50],
      [:nos, 'Olá! Aqui é a clínica. Acho que a mensagem veio para o número errado.', 49],
      [:cliente, 'Nossa, desculpa, foi engano!', 49]
    ]],
    ['so_um_link_parado', 'Loja de móveis planejados', :lixo, [
      [:cliente, 'https://bit.ly/3xYz9Qa', 72],
      [:nos, 'Olá! Recebemos seu link, em que podemos ajudar?', 71]
    ]],
    ['caractere_solto_parado', 'Clínica odontológica', :lixo, [
      [:cliente, '.', 80],
      [:nos, 'Olá! Tudo bem? Como podemos ajudar?', 79]
    ]],
    ['robo_com_robo', 'Corretora de seguros', :lixo, [
      [:nos, 'Olá! Sou a assistente virtual da corretora. Como posso ajudar?', 40],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Nosso horário de atendimento é de segunda a sexta, ' \
                 'das 8h às 18h. Retornaremos em breve.', 40],
      [:nos, 'Olá! Sou a assistente virtual da corretora. Como posso ajudar?', 39],
      [:cliente, 'Mensagem automática: obrigado pelo contato! Nosso horário de atendimento é de segunda a sexta, ' \
                 'das 8h às 18h. Retornaremos em breve.', 39]
    ]],
    ['parceiro_divulgacao', 'Escola de idiomas', :lixo, [
      [:cliente, 'Oi! Tenho um perfil de viagens com 80 mil seguidores e quero propor uma parceria: divulgo a escola ' \
                 'em troca de um curso. Vocês topam?', 26]
    ]],
    ['card_repetido', 'Loja de móveis planejados', :lixo, [
      [:cliente, 'Quero um orçamento de cozinha planejada para um apartamento de 9 m²', 3],
      [:nos, 'Claro! Vou separar as opções.', 3],
      [:cliente, 'Ok, aguardo o orçamento da cozinha', 2]
    ]],
    ['fechou_com_outra', 'Corretora de seguros', :perda, [
      [:cliente, 'Quero cotar o seguro do meu carro, um Onix 2022', 30],
      [:nos, 'Perfeito, já mando a cotação.', 29],
      [:nos, 'Segue a cotação: R$ 2.400 por ano.', 28],
      [:cliente, 'Obrigado, mas já fechei com outra corretora.', 1]
    ]],
    ['pedido_vago', 'Clínica odontológica', :negocio, [
      [:cliente, 'Quanto custa mais ou menos um clareamento?', 2]
    ]],
    ['so_nos_prospeccao', 'Loja de móveis planejados', :negocio, [
      [:nos, 'Olá, Paula! Vimos que você pediu informações sobre guarda-roupa planejado no nosso site. Posso ajudar?', 60],
      [:nos, 'Paula, ainda tem interesse no guarda-roupa? Temos condição especial este mês.', 30]
    ]],
    ['oi_agora', 'Escola de idiomas', :negocio, [
      [:cliente, 'oi', 0]
    ]],
    ['dois_pedidos_diferentes', 'Corretora de seguros', :negocio, [
      [:cliente, 'Quero cotar o seguro do carro', 5],
      [:nos, 'Claro! Qual o modelo?', 5],
      [:cliente, 'É um HB20 2021. E também quero cotar o seguro da minha casa, é outro pedido', 4]
    ]],
    ['fora_do_perfil', 'Clínica odontológica', :negocio, [
      [:cliente, 'Vocês fazem harmonização facial? Queria saber o preço', 6]
    ]],
    ['link_com_pedido', 'Loja de móveis planejados', :negocio, [
      [:cliente, 'https://pin.it/abc123', 20],
      [:cliente, 'Quero um painel de TV igual a esse, vocês fazem?', 20]
    ]]
  ].freeze

  # Card irmão aberto, mais antigo, na mesma conversa: o repetido (mesmo pedido) e o de outro pedido.
  IRMAOS = { 'card_repetido' => 'Orçamento de cozinha planejada', 'dois_pedidos_diferentes' => 'Seguro do HB20' }.freeze
  TITULOS = { 'card_repetido' => 'Cozinha planejada', 'dois_pedidos_diferentes' => 'Seguro residencial' }.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1922: o card que não é negócio sai do funil sem contar como perda' do
  let(:account) { create(:account, name: 'Conta Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Assistente') }

  around do |example|
    WebMock.allow_net_connect!
    with_modified_env(CRM_AI_ENABLED: 'true') { example.run }
  ensure
    WebMock.disable_net_connect!(allow_localhost: true)
  end

  before do
    skip 'eval pago: rode com CRM_EVAL_PAGO=1 e OPENAI_API_KEY' unless ENV['CRM_EVAL_PAGO'] == '1' && ENV['OPENAI_API_KEY'].present?

    allow(Crm::Config).to receive(:enabled?).and_return(true)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY').update!(value: ENV.fetch('OPENAI_API_KEY'))
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
    # O nosso robô aparece como agente da plataforma (platform_agent), como um agente da Autonom.ia ligado à caixa.
    allow_any_instance_of(Crm::Ai::ContextBuilder).to receive(:platform_bot_ids).and_return(Set[bot.id]) # rubocop:disable RSpec/AnyInstance
  end

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1922-nao-e-negocio.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    resultado = ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > NaoENegocioEval::TETO_USD

    resultado
  end

  def funil(ramo)
    pipeline = account.crm_pipelines.create!(name: ramo, created_by: admin, status: :active, when_to_use: "Clientes de #{ramo}",
                                             metadata: { 'ai' => { 'auto_move_enabled' => true } })
    NaoENegocioEval::ETAPAS.each_with_index do |(nome, criterio), posicao|
      account.crm_pipeline_stages.create!(pipeline: pipeline, name: nome, position: posicao, metadata: { 'ai_criteria' => criterio })
    end
    pipeline
  end

  def conversa_com(mensagens)
    contato = create(:contact, account: account, name: 'Contato Eval')
    conversa = create(:conversation, account: account, inbox: inbox, contact: contato, status: :open)
    mensagens.each do |quem, texto, horas|
      tipo = quem == :cliente ? :incoming : :outgoing
      create(:message, account: account, inbox: inbox, conversation: conversa, message_type: tipo, content: texto,
                       sender: quem == :cliente ? contato : bot, created_at: horas.hours.ago)
    end
    [conversa, contato]
  end

  def card(nome, ramo, mensagens)
    pipeline = funil(ramo)
    conversa, contato = conversa_com(mensagens)
    inicio = (mensagens.map(&:last).max + 1).hours.ago
    atributos = { pipeline: pipeline, stage: pipeline.stages.order(:position).first, contact: contato, inbox: inbox,
                  primary_conversation: conversa, created_at: inicio }
    account.crm_cards.create!(atributos.merge(title: NaoENegocioEval::IRMAOS[nome])) if NaoENegocioEval::IRMAOS[nome]
    account.crm_cards.create!(atributos.merge(title: NaoENegocioEval::TITULOS[nome] || 'Contato Eval'))
  end

  # ANTES: o prompt e o schema da base, sem a regra nem o campo.
  def como_antes
    schema = Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA
    corpo = schema[:schema]
    sem_campo = schema.merge(schema: corpo.merge(properties: corpo[:properties].except(:nao_e_negocio),
                                                 required: corpo[:required] - ['nao_e_negocio']))
    stub_const('Crm::Ai::StageClassifier::CLASSIFICATION_SCHEMA', sem_campo)
    allow(Crm::Ai::ClassifierPrompt).to receive(:para)
      .and_return(Crm::Ai::ClassifierPrompt::TEXT.delete_suffix("\n\n#{Crm::Ai::ClassifierPrompt::NAO_E_NEGOCIO}"))
  end

  def rodar(fase)
    NaoENegocioEval::CASOS.map do |nome, ramo, esperado, mensagens|
      alvo = card(nome, ramo, mensagens)
      decisao = nil
      allow(Crm::Ai::NaoENegocio).to receive(:new).and_wrap_original do |original, **args|
        decisao = args[:decisao]
        original.call(**args)
      end
      resultado = com_custo { Crm::Ai::Evaluator.new(card: alvo, trigger: 'message').perform }
      alvo.reload
      { fase: fase, nome: nome, ramo: ramo, esperado: esperado, status: resultado.status, erro: resultado.error,
        card_status: alvo.status, etapa: alvo.stage.name, nao_e_negocio: decisao }.tap { |linha| saida[:casos] << linha }
    end
  end

  def placar(linhas)
    linhas.group_by { |linha| linha[:esperado] }.transform_values do |grupo|
      { total: grupo.size, arquivados: grupo.count { |linha| linha[:card_status] == 'archived' },
        no_perdido: grupo.count { |linha| linha[:etapa] == 'Perdido' } }
    end
  end

  it 'antes x depois: lixo arquivado, negócio intacto, perda na etapa de perda' do
    depois = rodar('depois')
    saida[:placar_depois] = placar(depois)
    como_antes
    saida[:placar_antes] = placar(rodar('antes'))
    gravar_saida!

    expect(depois.select { |linha| linha[:esperado] != :lixo && linha[:card_status] == 'archived' }).to be_empty
    expect(depois.find { |linha| linha[:esperado] == :perda }[:etapa]).to eq('Perdido')
    expect(saida[:placar_depois][:lixo][:arquivados]).to be >= NaoENegocioEval::MINIMO_LIXO
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass

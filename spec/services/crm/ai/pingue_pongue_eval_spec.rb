require 'rails_helper'

# AVALIAÇÃO PAGA, DESLIGADA POR PADRÃO (CLAUDE.md do repo: eval com provedor pago só com execução explícita).
# Roda com `CRM_EVAL_PAGO=1` e `OPENAI_API_KEY`. Teto de US$ 2 (Rodrigo, #1606): a rodada para ao passar de
# US$ 1,80, somado pelo evento de custo da IA do CRM (Crm::Ai::UsageRecorder::EVENT_NAME).
#
# #1606, pingue-pongue: o cliente pediu uma pessoa, uma pessoa atendeu e devolveu à IA. Nas 10 mensagens seguintes,
# sem pedido novo, a IA do CRM (classificador real, avaliação real) NÃO pode pedir a passagem de novo. A mensagem de
# controle no fim (um pedido novo de verdade) tem de passar, senão "não passou" seria só um classificador que nunca
# passa. Modos: atribuição pela tela e convite aceito. Sem regra do funil a IA do CRM não passa conversa (quem passa
# é o agente): esse modo é da metade do Agentes IA.
#
# As saídas (o que o modelo decidiu em cada mensagem, custo e latência) vão para EVAL_SAIDA (JSON), para a
# verificação final do Multifunnel. Dados fictícios; nenhum prompt é gravado.
module PinguePongueEval
  TETO_USD = 1.80
  NEUTRAS = [
    'Obrigado pela ajuda, Ana!',
    'Então fica combinado assim.',
    'Vocês abrem no sábado?',
    'Qual o prazo de entrega para São Paulo?',
    'Tem desconto no pix?',
    'Pode me mandar o link do catálogo?',
    'Beleza, vou olhar com calma.',
    'Meu CEP é 01310-100, serve para o frete?',
    'Ok, entendi.',
    'Valeu, até mais.'
  ].freeze
  CONTROLE = 'Agora preciso falar com uma pessoa de novo, é outro problema: meu boleto veio errado.'.freeze
end

# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Eval pago #1606: pedido de pessoa atendido e devolvido não volta para a equipe' do
  let(:account) { create(:account, name: 'Loja Eval') }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Adm') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana') }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: false) }
  let(:bot) { create(:agent_bot, account: account, name: 'Assistente') }
  let(:contact) { create(:contact, account: account, name: 'Marina Souza') }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }

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
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)
    create(:inbox_member, inbox: inbox, user: ana)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return({ ana.id.to_s => 'online' })
  end

  after { Current.reset }

  def saida
    @saida ||= { inicio: Time.current.iso8601, casos: [], custo_usd: 0.0 }
  end

  def gravar_saida!
    caminho = ENV['EVAL_SAIDA'].presence || Rails.root.join('tmp/eval-1606-pingue-pongue.json').to_s
    FileUtils.mkdir_p(File.dirname(caminho))
    File.write(caminho, JSON.pretty_generate(saida.merge(fim: Time.current.iso8601)))
  end

  def com_custo(&)
    callback = ->(*, payload) { saida[:custo_usd] += payload[:cost].to_f }
    ActiveSupport::Notifications.subscribed(callback, Crm::Ai::UsageRecorder::EVENT_NAME, &)
    raise "teto do eval estourado: US$ #{saida[:custo_usd].round(4)}" if saida[:custo_usd] > PinguePongueEval::TETO_USD
  end

  def conversa_do_robo
    conversa = create(:conversation, account: account, inbox: inbox, contact: contact, status: :open).reload
    conversa.update!(ai_assignee: bot, assignee: nil)
    conversa
  end

  def card_com_regra(conversa, modo)
    pipeline, stage = vendas
    stage.update!(metadata: { 'ai_handoff' => { 'enabled' => true, 'handoff_mode' => modo,
                                                'trigger' => 'O cliente pede para falar com uma pessoa ou atendente humano.' } })
    account.crm_cards.create!(pipeline: pipeline, stage: stage, contact: contact, title: 'Pedido da Marina',
                              primary_conversation: conversa, inbox: inbox)
  end

  def fala(conversa, texto, quem:)
    tipo = quem == :cliente ? :incoming : :outgoing
    remetente = { cliente: contact, ana: ana, ia: bot }.fetch(quem)
    create(:message, account: account, inbox: inbox, conversation: conversa, message_type: tipo, content: texto, sender: remetente)
  end

  def atribuir(conversa, user)
    Current.user = user || ana
    Conversations::AssignmentService.new(conversation: conversa.reload, assignee_id: user&.id).perform
  ensure
    Current.user = nil
  end

  # Avaliação real do card (classificador + passagem). Devolve o que o modelo decidiu e o que aconteceu.
  def avaliar(card, conversa)
    decidido = nil
    allow(Crm::Ai::HandoffExecutor).to receive(:new).and_wrap_original do |original, **args|
      decidido = args[:handoff]
      original.call(**args)
    end
    inicio = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    com_custo { Crm::Ai::Evaluator.new(card: card.reload, trigger: 'manual').perform }
    ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - inicio) * 1000).round
    { intent: decidido&.dig(:intent) || decidido&.dig('intent'), motivo: decidido&.dig(:reason) || decidido&.dig('reason'),
      pessoa_no_nome: conversa.reload.assignee&.name, ms: ms }
  end

  # O começo comum: pedido de pessoa, a Ana atende, resolve e devolve.
  # ana_fala: false é o caso da conta 16 — a pessoa resolve fora do chat (telefone) e devolve sem escrever nada; no
  # histórico só ficam o pedido do cliente e o "vou chamar alguém" do assistente.
  def atendido_e_devolvido(modo, ana_fala: true)
    conversa = conversa_do_robo
    card = card_com_regra(conversa, modo)
    fala(conversa, 'Oi, quero falar com um atendente humano, por favor.', quem: :cliente)
    fala(conversa, 'Claro! Vou chamar alguém da equipe para você.', quem: :ia)
    yield conversa
    if ana_fala
      fala(conversa, 'Oi Marina, aqui é a Ana. Já ajustei o seu pedido, está tudo certo agora.', quem: :ana)
      fala(conversa, 'Perfeito, obrigada!', quem: :cliente)
      fala(conversa, 'Por nada! Vou te devolver para o nosso assistente, qualquer coisa é só chamar.', quem: :ana)
    end
    atribuir(conversa, nil)
    [conversa, card]
  end

  # Depois da devolução: 10 mensagens sem pedido novo e a de controle, cada uma com a avaliação real.
  def roteiro(nome, modo:, ana_fala: true, &)
    conversa, card = atendido_e_devolvido(modo, ana_fala: ana_fala, &)
    caso = { nome: nome, passagens: Crm::Passagens.recentes(conversa), turnos: [] }
    PinguePongueEval::NEUTRAS.each do |texto|
      fala(conversa, texto, quem: :cliente)
      caso[:turnos] << avaliar(card, conversa).merge(mensagem: texto, controle: false)
      atribuir(conversa, nil) if conversa.reload.assignee_id.present?
    end
    fala(conversa, PinguePongueEval::CONTROLE, quem: :cliente)
    caso[:turnos] << avaliar(card, conversa).merge(mensagem: PinguePongueEval::CONTROLE, controle: true)
    saida[:casos] << caso
    caso
  end

  def conferir(caso)
    neutros = caso[:turnos].reject { |turno| turno[:controle] }
    controle = caso[:turnos].find { |turno| turno[:controle] }
    expect(neutros.map { |turno| turno[:intent] }).not_to include('transferir')
    expect(neutros.filter_map { |turno| turno[:pessoa_no_nome] }).to be_empty
    expect(controle[:intent]).to eq('transferir')
  end

  it 'atribuição pela tela e convite aceito: 10 mensagens sem passagem nova, e o pedido novo passa' do # rubocop:disable RSpec/NoExpectationExample
    manual = roteiro('atribuicao_pela_tela', modo: 'r2_direct') { |conversa| atribuir(conversa, ana) }
    convite = roteiro('convite_aceito', modo: 'r3_invite') do |conversa|
      Crm::Passagens.registrar!(conversation: conversa, de: bot, para: ana, pedida_por: bot, motivo: 'convite')
      atribuir(conversa, ana)
    end
    fora_do_chat = roteiro('atendido_fora_do_chat', modo: 'r2_direct', ana_fala: false) { |conversa| atribuir(conversa, ana) }
    gravar_saida!

    conferir(manual)
    conferir(convite)
    conferir(fora_do_chat)
  ensure
    gravar_saida!
  end

  # Amostra longa do caso difícil (Multifunnel, 15/10: "10 turnos é amostra curta"): 3 conversas de 10 mensagens
  # sem pedido novo = 30, e o controle 3x. Critério: 0/30 com passagens e controle 3/3. Com EVAL_LINHA_DE_BASE=1 roda
  # sem passagens e só grava. Roda com EVAL_AMOSTRA_LONGA=1.
  it 'amostra longa: atendido fora do chat, 3 x 10 mensagens' do
    skip 'amostra longa: rode com EVAL_AMOSTRA_LONGA=1' unless ENV['EVAL_AMOSTRA_LONGA'] == '1'

    base = ENV['EVAL_LINHA_DE_BASE'] == '1'
    if base
      allow(Crm::Passagens).to receive(:recentes).and_return('')
      allow(Crm::Ai::DevolucaoAIa).to receive(:pelas_passagens).and_return(nil)
    end
    casos = Array.new(3) do |indice|
      nome = "#{base ? 'linha_de_base_' : ''}atendido_fora_do_chat_#{indice + 1}"
      roteiro(nome, modo: 'r2_direct', ana_fala: false) { |conversa| atribuir(conversa, ana) }
    end
    gravar_saida!
    casos.each { |caso| conferir(caso) } unless base
  ensure
    gravar_saida!
  end

  # Linha de base: o mesmo roteiro SEM o registro de passagens (como no main antes do #1606). Só grava o que o modelo
  # decidiu, para mostrar de onde vem o ganho; não confere nada. Roda com EVAL_LINHA_DE_BASE=1.
  it 'linha de base sem passagens: só grava' do
    skip 'linha de base: rode com EVAL_LINHA_DE_BASE=1' unless ENV['EVAL_LINHA_DE_BASE'] == '1'

    allow(Crm::Passagens).to receive(:recentes).and_return('')
    allow(Crm::Ai::DevolucaoAIa).to receive(:pelas_passagens).and_return(nil)
    roteiro('linha_de_base_atribuicao_pela_tela', modo: 'r2_direct') { |conversa| atribuir(conversa, ana) }
    roteiro('linha_de_base_convite_aceito', modo: 'r3_invite') do |conversa|
      Crm::Passagens.registrar!(conversation: conversa, de: bot, para: ana, pedida_por: bot, motivo: 'convite')
      atribuir(conversa, ana)
    end
    roteiro('linha_de_base_atendido_fora_do_chat', modo: 'r2_direct', ana_fala: false) { |conversa| atribuir(conversa, ana) }
  ensure
    gravar_saida!
  end
end
# rubocop:enable RSpec/DescribeClass

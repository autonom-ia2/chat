require 'rails_helper'

# #1922: o card que não é pedido de cliente sai do funil (arquivado) sem contar como perda, pela decisão do modelo na
# mesma avaliação de etapa; só no automático, com confiança alta, e nunca num card que uma pessoa já disse que vale.
RSpec.describe Crm::Ai::NaoENegocio do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account_and_admin) { create_account_and_user }
  let(:account) { account_and_admin.first }
  let(:admin) { account_and_admin.last }
  let(:funil_e_etapa) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => true } })
    [pipeline, stage]
  end
  let(:pipeline) { funil_e_etapa.first }
  let(:stage) { funil_e_etapa.last }
  let(:perdido) do
    create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 5).tap do |etapa|
      etapa.update!(metadata: { 'ai_criteria' => 'Cliente desistiu' })
    end
  end
  let(:conversa) { create(:conversation, account: account) }

  before { account.enable_features!(described_class::FLAG) }

  def novo_card(**atributos)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL', primary_conversation: conversa, **atributos)
  end

  # durante: o que acontece enquanto o modelo pensa (depois de a conversa ser lida para a avaliação).
  def ia_responde(nao_e_negocio, suggested_stage_id: stage.id, durante: nil, handoff: nil)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    resposta = { suggested_stage_id: suggested_stage_id, confidence: 0.9, reasoning: 'x', model_used: 'm',
                 nao_e_negocio: nao_e_negocio, handoff: handoff }.with_indifferent_access
    classificador = instance_double(Crm::Ai::StageClassifier)
    allow(classificador).to receive(:perform) do
      durante&.call
      resposta
    end
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  def lixo(confidence: 0.9, motivo: 'fora_do_negocio', duplicado_de: nil)
    { motivo: motivo, confidence: confidence, reasoning: 'Fornecedor oferecendo serviço para a empresa.', duplicado_de: duplicado_de }
  end

  def avaliar(card, trigger: 'message')
    Crm::Ai::Evaluator.new(card: card, trigger: trigger).perform
  end

  # Pega: o lixo ficar parado no funil ou ir para a etapa de perda (inflando a perda).
  it 'confiança alta: arquiva, não é perda, registra a IA e o motivo na linha do tempo', :aggregate_failures do
    card = novo_card
    ia_responde(lixo, suggested_stage_id: perdido.id)

    expect(avaliar(card).status).to eq(:archived)
    card.reload
    expect(card).to have_attributes(status: 'archived', stage_id: stage.id, closed_at: nil)
    atividade = Crm::Activity.where(card: card, event_type: 'archive').sole
    expect(atividade).to have_attributes(actor_type: 'system', actor_id: nil)
    expect(atividade.payload).to include('by' => 'ai', 'motivo' => 'fora_do_negocio', 'confidence' => 0.9)
    expect(Crm::Activity.where(card: card, event_type: %w[lost ai_auto_moved])).to be_empty
  end

  # Pega: o arquivamento valer numa conta sem a flag `crm_ia_arquiva_lixo` (o comportamento de antes tem de voltar inteiro).
  it 'conta sem a flag: o card fica onde está, aberto, e nada vai à linha do tempo', :aggregate_failures do
    account.disable_features!(described_class::FLAG)
    card = novo_card
    ia_responde(lixo)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
    expect(Crm::Activity.where(card: card, event_type: 'archive')).to be_empty
  end

  # Pega: o pedido de atendente sumir em silêncio porque o card foi arquivado antes da passagem (revisão do #1922).
  it 'pedido de atendente no mesmo card: não arquiva' do
    card = novo_card
    ia_responde(lixo, handoff: { intent: 'transferir', should_handoff: true, reason: 'Pediu uma pessoa', suggested_agent: nil })
    allow(Crm::Ai::HandoffExecutor).to receive(:new).and_return(instance_double(Crm::Ai::HandoffExecutor, perform: nil))

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: a sugestão de etapa que esperava uma pessoa continuar pendurada num card que saiu do funil.
  it 'a sugestão de etapa pendente do card arquivado expira' do
    card = novo_card
    sugestao = account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: perdido, confidence: 0.6,
                                                        reasoning: 'x', model_used: 'm', status: :pending)
    ia_responde(lixo)

    avaliar(card)

    expect(sugestao.reload).to be_expired
  end

  # Pega: arquivar com confiança média (só o automático com confiança alta tira o card do funil).
  it 'confiança abaixo da do movimento automático: não arquiva' do
    card = novo_card
    ia_responde(lixo(confidence: 0.7))

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to be_open
  end

  # Pega: arquivar num funil em que a IA só sugere.
  it 'funil sem movimento automático: não arquiva' do
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })
    card = novo_card
    ia_responde(lixo)

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: "Avaliar agora" (a pessoa olhando o card) arquivar o card sem ela pedir.
  it '"Avaliar agora": não arquiva' do
    card = novo_card
    ia_responde(lixo)

    avaliar(card, trigger: 'manual')

    expect(card.reload).to be_open
  end

  # Pega: motivo fora da lista (o código só aceita o que o schema define).
  it 'motivo desconhecido: não arquiva' do
    card = novo_card
    ia_responde(lixo(motivo: 'perda'))

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: a IA tirar do funil o que uma pessoa já disse que vale.
  describe 'card que uma pessoa já disse que vale' do
    it 'criado por uma pessoa: não arquiva' do
      card = Crm::Cards::Creator.new(account: account, user: admin, conversation: conversa,
                                     params: { pipeline_id: pipeline.id, stage_id: stage.id, title: 'Lead' }).perform
      ia_responde(lixo)

      avaliar(card)

      expect(card.reload).to be_open
    end

    it 'reaberto por uma pessoa (desfez o arquivamento da IA) há dias: não arquiva de novo' do
      card = novo_card
      travel_to(2.days.ago) do
        card.update!(status: :archived)
        Crm::Cards::Closer.new(card: card, actor: admin, result: 'reopen').perform
      end
      ia_responde(lixo)

      avaliar(card.reload)

      expect(card.reload).to be_open
    end

    it 'card com valor: não arquiva' do
      card = novo_card(value_cents: 150_000)
      ia_responde(lixo)

      avaliar(card)

      expect(card.reload).to be_open
    end

    it 'etapa mexida por uma pessoa há pouco (#1918): nem chega a decidir' do
      card = novo_card
      outra = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
      travel_to(1.hour.ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: outra).perform }
      ia_responde(lixo)

      expect(avaliar(card.reload)).to have_attributes(status: :skipped, error: 'pessoa_mexeu_na_etapa')
      expect(card.reload).to be_open
    end

    # Pega: o card movido por uma pessoa só ficar protegido nas horas do respeito ao movimento (#1918).
    it 'movido por uma pessoa há dias: não arquiva' do
      card = novo_card
      negociacao = create_crm_stage(account: account, pipeline: pipeline, name: 'Negociação', position: 1)
      travel_to(2.days.ago) { Crm::Cards::Mover.new(card: card, actor: admin, target_stage: negociacao).perform }
      ia_responde(lixo, suggested_stage_id: negociacao.id)

      avaliar(card.reload)

      expect(card.reload).to be_open
    end

    # Pega: o card em que uma pessoa trabalhou (editou, anotou) sair do funil por decisão da IA.
    it 'qualquer atividade de uma pessoa no card, há dias: não arquiva' do
      card = novo_card
      travel_to(3.days.ago) { Crm::ActivityLogger.new(card: card, actor: admin, event_type: 'update', payload: { title: 'Lead' }).perform }
      ia_responde(lixo)

      avaliar(card)

      expect(card.reload).to be_open
    end
  end

  # Pega: uma decisão velha arquivar o pedido que o cliente acabou de esclarecer, enquanto o modelo pensava.
  it 'mensagem do cliente chega enquanto a IA pensa: não arquiva' do
    card = novo_card
    ia_responde(lixo, durante: -> { create(:message, account: account, conversation: conversa, message_type: :incoming) })

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: os dois cards do mesmo pedido saírem do funil, sair o mais antigo, ou sair um pedido diferente.
  describe 'card repetido' do
    it 'arquiva só o mais novo, apontando o mais antigo; apontar o mais novo não arquiva', :aggregate_failures do
      antigo = novo_card
      novo = novo_card
      ia_responde(lixo(motivo: 'duplicado', duplicado_de: novo.id))
      expect(avaliar(antigo).status).not_to eq(:archived)

      ia_responde(lixo(motivo: 'duplicado', duplicado_de: antigo.id))
      expect(avaliar(novo).status).to eq(:archived)
      expect([antigo.reload.status, novo.reload.status]).to eq(%w[open archived])
    end

    it 'repetido de um card de outra conversa vinculada a este' do
      outra = create(:conversation, account: account)
      antigo = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', primary_conversation: outra)
      novo = novo_card
      Crm::CardConversation.create!(account: account, card: novo, conversation: outra)
      ia_responde(lixo(motivo: 'duplicado', duplicado_de: antigo.id))

      expect(avaliar(novo).status).to eq(:archived)
      expect(antigo.reload).to be_open
    end

    it 'sem apontar qual card fica: não arquiva' do
      novo_card
      card = novo_card
      ia_responde(lixo(motivo: 'duplicado'))

      avaliar(card)

      expect(card.reload).to be_open
    end

    # Pega: no multifunil, a mesma conversa com pedidos de funis diferentes (o modelo erra e diz "repetido").
    it 'o card apontado é de outro funil: não arquiva' do
      outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      antigo = account.crm_cards.create!(pipeline: outro_funil, stage: outra_etapa, title: 'Lead', primary_conversation: conversa)
      card = novo_card
      ia_responde(lixo(motivo: 'duplicado', duplicado_de: antigo.id))

      avaliar(card)

      expect(card.reload).to be_open
    end

    # Pega: o card apontado já saiu do funil (o repetido de um repetido): os dois sumiriam.
    it 'o card apontado não está aberto: não arquiva' do
      antigo = novo_card
      antigo.update!(status: :archived)
      card = novo_card
      ia_responde(lixo(motivo: 'duplicado', duplicado_de: antigo.id))

      avaliar(card)

      expect(card.reload).to be_open
    end
  end

  # Pega: o card arquivado pela IA não ter como voltar.
  it 'desfazer: reabrir pelo caminho de sempre volta o card ao funil' do
    card = novo_card
    ia_responde(lixo)
    avaliar(card)

    Crm::Cards::Closer.new(card: card.reload, actor: admin, result: 'reopen').perform

    expect(card.reload).to have_attributes(status: 'open', closed_at: nil, stage_id: stage.id)
  end

  # #2395: a conversa cujo card mais novo a IA arquivou como "fora_do_negocio" não recria card sozinha (CardSyncer).
  describe '.conversa_fora_do_negocio?' do
    def arquivar(card, actor: nil, **payload)
      Crm::Cards::Archiver.new(card: card, actor: actor, payload: payload).perform
    end

    def pela_ia(card) = arquivar(card, by: 'ai', motivo: 'fora_do_negocio')

    it 'vale para o card ligado à conversa só pelo vínculo (crm_card_conversations)' do
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Lead', currency: 'BRL')
      Crm::CardConversation.create!(account: account, card: card, conversation: conversa)
      pela_ia(card)

      expect(described_class.conversa_fora_do_negocio?(conversa)).to be(true)
    end

    # Intencional: o bloqueio é da conversa, não do funil. O card mais novo, de qualquer funil, decide.
    it 'vale para a conversa inteira quando ela tem cards em dois funis' do
      outro_funil, outra_etapa = create_crm_pipeline(account: account, user: admin, name: 'Pós-venda')
      novo_card(status: :lost, closed_at: 1.day.ago)
      pela_ia(account.crm_cards.create!(pipeline: outro_funil, stage: outra_etapa, title: 'Lead', currency: 'BRL',
                                        primary_conversation: conversa))

      expect(described_class.conversa_fora_do_negocio?(conversa)).to be(true)
    end

    # Prazo do bloqueio (decisão do Rodrigo, 30/10): 30 dias a contar do arquivamento da IA.
    def arquivado_ha(tempo)
      card = novo_card
      pela_ia(card)
      Crm::Activity.where(card: card, event_type: 'archive').update_all(created_at: tempo.ago) # rubocop:disable Rails/SkipsModelValidations
    end

    it 'bloqueia com o arquivamento da IA dentro dos 30 dias' do
      arquivado_ha(described_class::BLOQUEIO_DA_RECRIACAO - 1.hour)

      expect(described_class.conversa_fora_do_negocio?(conversa)).to be(true)
    end

    it 'libera com o arquivamento da IA de mais de 30 dias' do
      arquivado_ha(described_class::BLOQUEIO_DA_RECRIACAO + 1.hour)

      expect(described_class.conversa_fora_do_negocio?(conversa)).to be(false)
    end

    it 'libera quando uma pessoa reabriu e arquivou o card depois da IA' do
      card = novo_card
      pela_ia(card)
      card.update!(status: :open)
      arquivar(card, actor: admin)

      expect(described_class.conversa_fora_do_negocio?(conversa)).to be(false)
    end
  end
end

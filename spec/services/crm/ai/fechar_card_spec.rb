require 'rails_helper'

# IA entende a conversa F3 (flag `crm_ia_fecha_card`): a IA de etapa fecha o card pela decisão do modelo na mesma
# avaliação. Perdido com motivo em qualquer funil, Resolvido só em funil de Atender, Ganho nunca; só no automático, com
# confiança alta, e nunca por cima de uma pessoa ou de mensagem nova. O modelo é simulado: aqui se prova o código.
RSpec.describe Crm::Ai::FecharCard do
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
  let(:conversa) { create(:conversation, account: account) }

  before { account.enable_features!(described_class::FLAG) }

  def novo_card(funil: pipeline, etapa: stage, **atributos)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Pedido', currency: 'BRL', primary_conversation: conversa, **atributos)
  end

  def funil_de_atender
    funil = account.crm_pipelines.create!(name: 'Atendimento', created_by: admin, status: :active, counts_as_sale: false,
                                          metadata: { 'ai' => { 'auto_move_enabled' => true } })
    [funil, account.crm_pipeline_stages.create!(pipeline: funil, name: 'Aberto', position: 0)]
  end

  # durante: o que acontece enquanto o modelo pensa (depois de a conversa ser lida para a avaliação).
  def ia_responde(fechar_card, suggested_stage_id: nil, durante: nil, handoff: nil)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: true, resolve: { api_key: 'test' })
    )
    resposta = { suggested_stage_id: suggested_stage_id, confidence: 0.9, reasoning: 'x', model_used: 'm',
                 fechar_card: fechar_card, handoff: handoff }.with_indifferent_access
    classificador = instance_double(Crm::Ai::StageClassifier)
    allow(classificador).to receive(:perform) do
      durante&.call
      resposta
    end
    allow(Crm::Ai::StageClassifier).to receive(:new).and_return(classificador)
    allow(Crm::Cards::CurrentSubject).to receive(:card?).and_return(true)
  end

  def fim(resultado: 'perdido', motivo: 'recusou', confidence: 0.9, retorno_em: nil)
    { resultado: resultado, motivo: motivo, retorno_em: retorno_em, confidence: confidence, reasoning: 'O cliente disse que não quer.' }
  end

  def avaliar(card, trigger: 'message')
    Crm::Ai::Evaluator.new(card: card, trigger: trigger).perform
  end

  # Pega: o "Perdido" da IA ser só uma coluna, com o card aberto e sem motivo (achado H4 do placar).
  it 'perdido: fecha como Perdido, com o motivo na língua da conta e a IA na linha do tempo', :aggregate_failures do
    account.update!(locale: 'pt_BR')
    card = novo_card
    ia_responde(fim(motivo: 'fechou_com_outra'), suggested_stage_id: stage.id)

    expect(avaliar(card).status).to eq(:closed)
    expect(card.reload).to have_attributes(status: 'lost', lost_reason: 'Fechou com outra empresa')
    expect(card.closed_at).to be_present
    atividade = Crm::Activity.where(card: card, event_type: 'lost').sole
    expect(atividade).to have_attributes(actor_type: 'system', actor_id: nil)
    expect(atividade.payload)
      .to include('by' => 'ai', 'motivo' => 'fechou_com_outra', 'confidence' => 0.9, 'lost_reason' => 'Fechou com outra empresa')
    expect(atividade.payload).to have_key('closed_with')
  end

  # Pega: o card fechado ficar na etapa do meio quando o funil tem a etapa de perda (o quadro mente).
  it 'perdido num funil com etapa de perda: o card vai para ela antes de fechar', :aggregate_failures do
    perda = create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9).tap { |etapa| etapa.update!(is_lost_stage: true) }
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to have_attributes(stage_id: perda.id, status: 'lost')
    expect(Crm::Activity.where(card: card, event_type: 'move', actor_type: 'system')).to exist
  end

  # Pega: o perdido de um funil de Atender virar "lost" (venda) em vez de Cancelado.
  it 'perdido num funil de Atender: fecha como Cancelado' do
    funil, etapa = funil_de_atender
    card = novo_card(funil: funil, etapa: etapa)
    ia_responde(fim(motivo: 'adiou'), suggested_stage_id: etapa.id)

    avaliar(card)

    expect(card.reload).to have_attributes(status: 'cancelled', lost_reason: 'Postponed')
  end

  # Pega (regra j): o atendimento resolvido continuar aberto, e ir para a etapa de fim do funil de Atender.
  it 'resolvido num funil de Atender: fecha como Resolvido, na etapa de fim', :aggregate_failures do
    funil, etapa = funil_de_atender
    final = create_crm_stage(account: account, pipeline: funil, name: 'Resolvido', position: 5).tap { |e| e.update!(is_won_stage: true) }
    card = novo_card(funil: funil, etapa: etapa)
    ia_responde(fim(resultado: 'resolvido', motivo: nil), suggested_stage_id: etapa.id)

    expect(avaliar(card).status).to eq(:closed)
    expect(card.reload).to have_attributes(status: 'resolved', stage_id: final.id, lost_reason: nil)
    expect(Crm::Activity.where(card: card, event_type: 'resolved').sole.payload).to include('by' => 'ai')
  end

  # Pega (regra c): a IA marcar Ganho. Num funil de venda, "resolvido" seria ganho: o código recusa e o card segue aberto.
  it 'resolvido num funil de venda: não fecha (a IA nunca marca Ganho)', :aggregate_failures do
    card = novo_card
    ia_responde(fim(resultado: 'resolvido', motivo: nil), suggested_stage_id: stage.id)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to be_open
    expect(Crm::Activity.where(card: card, event_type: %w[won resolved])).to be_empty
  end

  it 'resultado fora da lista (ganho): não fecha' do
    card = novo_card
    ia_responde(fim(resultado: 'ganho', motivo: nil), suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  it 'perdido sem motivo da lista: não fecha' do
    card = novo_card
    ia_responde(fim(motivo: nil), suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: o fechamento valer numa conta sem a flag (o comportamento de antes tem de voltar inteiro).
  it 'conta sem a flag: nada fecha', :aggregate_failures do
    account.disable_features!(described_class::FLAG)
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    expect(avaliar(card)).to have_attributes(status: :skipped, error: 'same_stage')
    expect(card.reload).to be_open
  end

  it 'confiança abaixo da do movimento automático: não fecha' do
    card = novo_card
    ia_responde(fim(confidence: 0.7), suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  it 'funil sem movimento automático: não fecha' do
    pipeline.update!(metadata: { 'ai' => { 'auto_move_enabled' => false } })
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: "Avaliar agora" (a pessoa olhando o card) fechar o card sem ela pedir.
  it '"Avaliar agora": não fecha' do
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card, trigger: 'manual')

    expect(card.reload).to be_open
  end

  # Pega (regra i): silêncio virar Perdido. A avaliação do card parado nunca fecha.
  it 'avaliação do card parado: não fecha' do
    card = novo_card
    ia_responde(fim(motivo: 'adiou'), suggested_stage_id: stage.id)

    avaliar(card, trigger: described_class::TRIGGER_CARD_PARADO)

    expect(card.reload).to be_open
  end

  # Pega (revisão adversarial F3): o fechamento barrado deixar o card ABERTO na coluna de perda, sem motivo nem retorno,
  # porque a etapa de fim que veio junto moveu sozinha (o achado H4, agora causado pela própria regra de fechar).
  describe 'fechamento barrado com a etapa de fim junto' do
    let(:perda) do
      create_crm_stage(account: account, pipeline: pipeline, name: 'Perdido', position: 9)
        .tap { |etapa| etapa.update!(is_lost_stage: true, metadata: { 'ai_criteria' => 'O cliente desistiu.' }) }
    end

    it 'card parado: não move sozinho para a perda; vira sugestão', :aggregate_failures do
      card = novo_card
      ia_responde(fim(motivo: 'adiou'), suggested_stage_id: perda.id)

      resultado = avaliar(card, trigger: described_class::TRIGGER_CARD_PARADO)

      expect(resultado.status).to eq(:suggested)
      expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
    end

    it 'mensagem nova do cliente: não move sozinho para a perda', :aggregate_failures do
      card = novo_card
      nova = -> { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Espera') }
      ia_responde(fim, suggested_stage_id: perda.id, durante: nova)

      expect(avaliar(card).status).to eq(:suggested)
      expect(card.reload).to have_attributes(status: 'open', stage_id: stage.id)
    end

    it 'sem a flag: a etapa de perda move como sempre' do
      account.disable_features!(described_class::FLAG)
      card = novo_card
      ia_responde(fim, suggested_stage_id: perda.id)

      expect(avaliar(card).status).to eq(:auto_moved)
    end
  end

  # Pega: o pedido de pessoa sumir porque o card fechou antes da passagem.
  it 'pedido de pessoa na mesma resposta: não fecha' do
    card = novo_card
    ia_responde(fim, suggested_stage_id: stage.id,
                     handoff: { intent: 'transferir', should_handoff: true, reason: 'Pediu uma pessoa', suggested_agent: nil })
    allow(Crm::Ai::HandoffExecutor).to receive(:new).and_return(instance_double(Crm::Ai::HandoffExecutor, perform: nil))

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: a decisão velha valer depois de o cliente escrever de novo enquanto o modelo pensava.
  it 'mensagem nova do cliente enquanto o modelo pensava: não fecha' do
    card = novo_card
    nova = -> { create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, content: 'Espera') }
    ia_responde(fim, suggested_stage_id: stage.id, durante: nova)

    avaliar(card)

    expect(card.reload).to be_open
  end

  # Pega: a IA fechar por cima de uma pessoa que acabou de reabrir o card.
  it 'reaberto por uma pessoa há pouco: não fecha' do
    card = novo_card
    Crm::ActivityLogger.new(card: card, actor: admin, event_type: 'reopen', payload: {}).perform
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(card.reload).to be_open
  end

  it 'a sugestão de etapa pendente do card fechado expira' do
    card = novo_card
    outra = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta', position: 1)
    sugestao = account.crm_ai_stage_suggestions.create!(card: card, from_stage: stage, to_stage: outra, confidence: 0.6,
                                                        reasoning: 'x', model_used: 'm', status: :pending)
    ia_responde(fim, suggested_stage_id: stage.id)

    avaliar(card)

    expect(sugestao.reload).to be_expired
  end

  describe '.fechados_pela_ia' do
    it 'traz o card fechado pela IA e tira o que uma pessoa fechou ou reabriu depois', :aggregate_failures do
      pela_ia = novo_card
      depois_pela_pessoa = novo_card
      pela_pessoa = novo_card
      [pela_ia, depois_pela_pessoa].each do |card|
        Crm::Cards::Closer.new(card: card, actor: nil, result: 'lost', payload_extra: { by: 'ai' }).perform
      end
      Crm::ActivityLogger.new(card: depois_pela_pessoa, actor: admin, event_type: 'reopen', payload: {}).perform
      Crm::Cards::Closer.new(card: pela_pessoa, actor: admin, result: 'lost').perform

      expect(described_class.fechados_pela_ia(account, 1.hour.ago)).to eq([pela_ia.id])
    end
  end
end

require 'rails_helper'

RSpec.describe Crm::FollowUps::AutoFollowupPlanner do
  def setup_pipeline(account:, user:, config:)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    pipeline.update!(metadata: { 'ai' => { 'auto_followup' => config.stringify_keys } })
    [pipeline, stage]
  end

  # Conversa WhatsApp-capaz (WAHA, sem janela de 24h) com o número de mensagens de cada lado que o
  # teste precisar, para exercitar a exigência de mão dupla real. account/user/pipeline saem do
  # próprio stage para caber no limite de parâmetros (Metrics/ParameterLists).
  def build_card_with_exchange(stage:, anchor_at:, inbound_count: 2, outbound_count: 2, contact_tz: nil)
    pipeline = stage.pipeline
    account = pipeline.account
    user = pipeline.created_by
    inbox = create_crm_whatsapp_api_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    contact.update!(additional_attributes: { 'timezone' => contact_tz }) if contact_tz
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    inbound_count.times { create_incoming_message(conversation: conversation) }
    outbound_count.times do
      conversation.messages.create!(account_id: account.id, inbox_id: inbox.id, message_type: :outgoing, content: 'Oi')
    end
    # A âncora da cadência é a ÚLTIMA mensagem real da conversa (CadenceAnchor), não a última do
    # cliente: por isso o fixture envelhece a mensagem mais recente, seja ela de quem for.
    conversation.messages.reorder(id: :desc).first&.update!(created_at: anchor_at)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    [card, conversation]
  end

  # Config padrão para os testes de elegibilidade: quiet_hours cobre o dia inteiro (start=0, end=24)
  # para não interferir no cálculo do due_at — a janela de silêncio tem teste dedicado abaixo.
  def eligible_config(overrides = {})
    { 'enabled' => true, 'intervals_hours' => [20, 72, 168], 'max_touches' => 3,
      'quiet_hours' => { 'start' => 0, 'end' => 24 } }.merge(overrides)
  end

  it 'funil com auto_followup.enabled false retorna 0 e não cria nada' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: { 'enabled' => false })
    build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)

    result = described_class.new(pipeline: pipeline).perform

    expect(result).to eq(0)
    expect(Crm::FollowUp.count).to eq(0)
  end

  it 'card elegível cria o toque 1 (touch=1, source=ai_followup) e o result soma 1' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)

    result = described_class.new(pipeline: pipeline).perform

    expect(result).to eq(1)
    follow_up = card.reload.follow_ups.sole
    expect(follow_up.metadata['source']).to eq('ai_followup')
    expect(follow_up.metadata['touch']).to eq(1)
  end

  it 'card elegível grava o state completo do card com active=true' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)

    described_class.new(pipeline: pipeline).perform

    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['active']).to be(true)
    expect(state['spent']).to be(false)
    expect(state['touch']).to eq(1)
    expect(state['max_touches']).to eq(3)
    expect(state['next_due_at']).to be_present
  end

  it 'conversa com troca insuficiente (1 inbound) NÃO cria o toque' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    build_card_with_exchange(stage: stage, inbound_count: 1, outbound_count: 2, anchor_at: 21.hours.ago)

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(Crm::FollowUp.count).to eq(0)
  end

  # O motivo da mudança de âncora: o relógio conta da ÚLTIMA MENSAGEM da conversa, não da última
  # fala do cliente. Sem isto, o time podia estar conversando com o cliente agora e o toque saía
  # por cima, porque o relógio tinha começado a correr horas antes.
  it 'mensagem recente do time adia o toque, mesmo com o cliente calado há muito tempo' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    _card, conversation = build_card_with_exchange(stage: stage, anchor_at: 30.hours.ago)
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id,
                                  message_type: :outgoing, content: 'Estou verificando aqui, já te falo')

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
  end

  # Mas o toque da própria IA NÃO é conversa: se contasse, cada toque viraria a âncora do seguinte
  # e o espaçamento configurado pelo usuário mudaria sozinho.
  it 'follow-up automático anterior não conta como âncora' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, conversation = build_card_with_exchange(stage: stage, anchor_at: 30.hours.ago)
    conversation.messages.create!(account_id: account.id, inbox_id: conversation.inbox_id,
                                  message_type: :outgoing, content: 'Toque automático anterior')
                .update!(content_attributes: { 'crm_follow_up_id' => 999 })

    expect(described_class.new(pipeline: pipeline).perform).to eq(1)
    expect(card.reload.follow_ups.count).to eq(1)
  end

  it 'última mensagem recente demais (dentro do primeiro intervalo) NÃO cria o toque' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    build_card_with_exchange(stage: stage, anchor_at: 1.hour.ago)

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(Crm::FollowUp.count).to eq(0)
  end

  it 'card com state.spent=true NUNCA re-arma, mesmo com exigências de elegibilidade satisfeitas' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'spent' => true } } })

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(card.reload.follow_ups.count).to eq(0)
  end

  # LGPD: quem pediu para parar não pode ser re-armado pela varredura seguinte. Sem esta guarda o
  # cancelador marcava opted_out, a cadência morria, e o planner criava um ciclo novo do zero —
  # zerando a própria marca de opt-out. Só o RESET manual do drawer re-arma.
  it 'card com opted_out=true NUNCA re-arma pela varredura' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => false, 'spent' => false,
                                                                  'opted_out' => true } } })

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(card.reload.follow_ups.count).to eq(0)
    expect(card.metadata['ai']['auto_followup_state']['opted_out']).to be(true)
  end

  # Guarda de produto: o cliente já disse QUANDO volta (ai_callback com due_at futuro) — não
  # perturbar com a cadência genérica antes desse retorno agendado disparar.
  it 'card com ai_callback ativo e due_at futuro NÃO cria o toque' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, conversation = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Retorno agendado', due_at: 3.days.from_now,
      timezone: 'UTC', automation_mode: :reminder_only, metadata: { 'source' => 'ai_callback' }
    )

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(card.reload.follow_ups.none? { |fu| fu.metadata['source'] == 'ai_followup' }).to be(true)
  end

  # --- Ataque: shapes adversariais de metadata ---------------------------------------------

  it 'card sem auto_followup_state (metadata["ai"] ausente) é elegível normalmente' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)
    card.update!(metadata: {})

    expect(described_class.new(pipeline: pipeline).perform).to eq(1)
    expect(card.reload.follow_ups.count).to eq(1)
  end

  # O valor vem de jsonb: um "true" string (backfill, round-trip externo) precisa contar igual ao
  # booleano. Guarda de consentimento falha para o lado FECHADO — com igualdade estrita ela
  # re-armava em silêncio quem pediu para sair.
  it 'opted_out gravado como STRING "true" também bloqueia o re-armamento' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user, config: eligible_config)
    card, = build_card_with_exchange(stage: stage, anchor_at: 21.hours.ago)
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => false, 'spent' => false,
                                                                  'opted_out' => 'true' } } })

    expect(described_class.new(pipeline: pipeline).perform).to eq(0)
    expect(card.reload.follow_ups.count).to eq(0)
  end

  # Multi-tenant: um pipeline pertence a UMA conta (FK); o model enforça isso via
  # linked_records_must_belong_to_account. Prova que a varredura não corre risco de vazamento
  # cross-tenant porque a própria persistência recusa o card antes de chegar ao planner.
  it 'card de OUTRA conta não pode ser anexado ao pipeline de outra conta (guarda no model, não no planner)' do
    account_a, user_a = create_account_and_user
    account_b, user_b = create_account_and_user
    pipeline_a, stage_a = setup_pipeline(account: account_a, user: user_a, config: eligible_config)
    inbox_b = create_crm_whatsapp_api_inbox(account: account_b, members: [user_b])
    contact_b = account_b.contacts.create!(name: 'Lead B', phone_number: '+5511900000000')
    conversation_b = create_crm_conversation(account: account_b, inbox: inbox_b, contact: contact_b, assignee: user_b)

    card = account_b.crm_cards.new(
      pipeline: pipeline_a, stage: stage_a, inbox: inbox_b, contact: contact_b,
      primary_conversation: conversation_b, title: 'Vazamento'
    )

    expect(card).not_to be_valid
    expect(card.errors[:pipeline]).to include('must belong to the same account')
  end

  it 'due_at que cairia fora da janela de quiet_hours é empurrado para dentro dela' do
    account, user = create_account_and_user
    pipeline, stage = setup_pipeline(account: account, user: user,
                                     config: { 'enabled' => true, 'intervals_hours' => [20, 72, 168],
                                               'max_touches' => 3, 'quiet_hours' => { 'start' => 8, 'end' => 20 } })
    now = Time.utc(2026, 8, 10, 5, 0, 0)
    # last_inbound 21h antes de `now`: toque 1 cairia às 4h UTC (1h local em America/Sao_Paulo,
    # UTC-3) — dentro da janela silenciosa [0h,8h) — então precisa ser empurrado para 8h local.
    card, = build_card_with_exchange(stage: stage, anchor_at: now - 21.hours, contact_tz: 'America/Sao_Paulo')

    described_class.new(pipeline: pipeline, now: now).perform

    follow_up = card.reload.follow_ups.sole
    expect(follow_up.due_at.utc).to be_within(1.second).of(Time.utc(2026, 8, 10, 11, 0, 0))
  end
end

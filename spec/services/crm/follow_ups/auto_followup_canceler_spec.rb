require 'rails_helper'

RSpec.describe Crm::FollowUps::AutoFollowupCanceler do
  def build_card(account:, user:, active:)
    inbox = create_crm_inbox(account: account, members: [user])
    contact = account.contacts.create!(name: 'Lead', phone_number: "+55119#{rand(10_000_000..99_999_999)}")
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user)
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    card = account.crm_cards.create!(
      pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
      primary_conversation: conversation, title: 'Lead'
    )
    card.update!(metadata: { 'ai' => { 'auto_followup_state' => { 'active' => active } } })
    [card, conversation]
  end

  def build_follow_up(account:, card:, conversation:, source:)
    account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: "Toque #{source}", due_at: 1.hour.from_now,
      timezone: 'UTC', automation_mode: :reminder_only, metadata: { 'source' => source }
    )
  end

  def create_outgoing_message(conversation:, content: 'Já te retorno')
    conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :outgoing, content: content
    )
  end

  it 'cancela TODOS os follow-ups ai_followup ativos quando o contato responde e grava o state de parada' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch1 = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    touch2 = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi, ainda tenho interesse')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch1.reload.status).to eq('canceled')
    expect(touch2.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['active']).to be(false)
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  # Risco real de regressão: um retorno manual ou um ai_callback (retorno por data que o próprio
  # cliente pediu) NUNCA pode ser cancelado pela resposta que disparou a cadência genérica.
  it 'NÃO cancela follow-ups de outra origem (manual ou ai_callback) ao processar a resposta' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    manual = build_follow_up(account: account, card: card, conversation: conversation, source: 'manual')
    callback = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_callback')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    expect(manual.reload.status).to eq('pending')
    expect(callback.reload.status).to eq('pending')
  end

  it 'mensagem OUTGOING não cancela nada nem altera o state' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_outgoing_message(conversation: conversation)

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('pending')
    expect(card.reload.metadata['ai']['auto_followup_state']['active']).to be(true)
  end

  it 'cadência inativa (state.active != true) não cancela nada' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: false)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('pending')
  end

  it 'opt-out por palavra EXATA da lista grava opted_out=true e stopped_reason=opt_out' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: '  Sair  ')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  # Palavra solta só vale quando é a mensagem inteira; frase vale em qualquer posição. Aqui o
  # texto contém a sequência "parar" dentro de "preparar" e segue sendo resposta comum.
  it 'palavra-alvo aparecendo apenas dentro de outra palavra conta como reply normal' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'vou preparar seu pedido, já te aviso')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  it 'frase de opt-out dentro de texto maior aciona via OPT_OUT_PHRASES ("pode parar por favor")' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'pode parar por favor')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  it 'frase de opt-out dentro de texto maior aciona via OPT_OUT_PHRASES ("não quero mais receber")' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Não quero mais receber essas mensagens')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  # O motivo de a palavra solta exigir a mensagem inteira: "sair" e "cancelar" aparecem o tempo
  # todo em frase comum. Marcar isso como opt_out sujaria justamente o número que uma auditoria
  # de LGPD vai olhar. A cadência para nos dois casos — o que muda é só o rótulo.
  it 'uso comum de "sair" e "cancelar" dentro de frase conta como reply normal, não opt-out' do
    account, user = create_account_and_user
    ['vou sair agora, te respondo depois', 'quero cancelar minha reunião de amanhã'].each do |texto|
      card, conversation = build_card(account: account, user: user, active: true)
      touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
      message = create_incoming_message(conversation: conversation, content: texto)

      described_class.new(card: card, message: message).maybe_cancel

      expect(touch.reload.status).to eq('canceled')
      state = card.reload.metadata['ai']['auto_followup_state']
      expect(state['stopped_reason']).to eq('replied')
      expect(state['opted_out']).to be(false)
    end
  end

  # O oposto: a mesma palavra sozinha É a forma canônica de opt-out do WhatsApp.
  it 'palavra de opt-out sozinha na mensagem aciona opt_out' do
    account, user = create_account_and_user
    %w[PARAR cancelar unsubscribe].each do |texto|
      card, conversation = build_card(account: account, user: user, active: true)
      build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
      message = create_incoming_message(conversation: conversation, content: texto)

      described_class.new(card: card, message: message).maybe_cancel

      expect(card.reload.metadata['ai']['auto_followup_state']['stopped_reason']).to eq('opt_out')
    end
  end

  # Formas comuns de recusa em português que o match exato deixava passar direto. Cada uma delas
  # significa "não me mande mais" e precisa virar opt-out registrado, não só cadência cancelada.
  it 'reconhece as formas escritas por extenso de pedido para parar' do
    account, user = create_account_and_user
    ['Não me envie mais mensagens', 'por favor, remova meu número da lista',
     'não quero receber mensagens de vocês'].each do |texto|
      card, conversation = build_card(account: account, user: user, active: true)
      build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
      message = create_incoming_message(conversation: conversation, content: texto)

      described_class.new(card: card, message: message).maybe_cancel

      state = card.reload.metadata['ai']['auto_followup_state']
      expect(state['stopped_reason']).to eq('opt_out'), "esperava opt_out para: #{texto}"
      expect(state['opted_out']).to be(true)
    end
  end

  it 'registra a atividade ai_followup_stopped com o motivo do cancelamento' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'Oi')

    described_class.new(card: card, message: message).maybe_cancel

    activity = card.activities.find_by(event_type: 'ai_followup_stopped')
    expect(activity).to be_present
    expect(activity.payload['reason']).to eq('replied')
    expect(activity.payload['trigger']).to eq('inbound_reply')
  end

  # --- Ataque: casos adversariais de conteúdo de mensagem -----------------------------------

  it 'mensagem incoming sem conteúdo (nil) cancela a cadência como reply comum, sem estourar erro' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = conversation.messages.create!(
      account_id: conversation.account_id, inbox_id: conversation.inbox_id,
      message_type: :incoming, content: nil, sender: conversation.contact
    )

    expect { described_class.new(card: card, message: message).maybe_cancel }.not_to raise_error

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  it 'mensagem só com espaços/pontuação (sem texto real) conta como reply comum, não opt-out' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: '   !!!   ')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  it 'mensagem só com emoji não é reconhecida como opt-out (fora das listas)' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: '👍👍👍')

    expect { described_class.new(card: card, message: message).maybe_cancel }.not_to raise_error

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('replied')
    expect(state['opted_out']).to be(false)
  end

  it 'MAIÚSCULAS + acento + pontuação múltipla ("NÃO QUERO MAIS RECEBER!!!") ainda aciona opt_out' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: 'NÃO QUERO MAIS RECEBER!!!')

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  it 'frase de opt-out escondida no MEIO de uma mensagem longa ainda aciona opt_out' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    texto = 'Bom dia! Tudo bem por aí? Olha, pare de mandar essas mensagens, por favor, valeu, um abraço'
    message = create_incoming_message(conversation: conversation, content: texto)

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  it 'palavra-alvo isolada mas cercada de quebras de linha ainda casa como palavra EXATA' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    touch = build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    message = create_incoming_message(conversation: conversation, content: "\n  SAIR  \n")

    described_class.new(card: card, message: message).maybe_cancel

    expect(touch.reload.status).to eq('canceled')
    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
    expect(state['opted_out']).to be(true)
  end

  it 'quebras de linha NO MEIO do texto não impedem o match de palavra EXATA' do
    account, user = create_account_and_user
    card, conversation = build_card(account: account, user: user, active: true)
    build_follow_up(account: account, card: card, conversation: conversation, source: 'ai_followup')
    # "sair" sozinho span múltiplas linhas antes/depois — mas SEM outro texto: continua sendo a
    # mensagem inteira depois de colapsar \s+ (que inclui \n) em espaço único.
    message = create_incoming_message(conversation: conversation, content: "sair\n\n")

    described_class.new(card: card, message: message).maybe_cancel

    state = card.reload.metadata['ai']['auto_followup_state']
    expect(state['stopped_reason']).to eq('opt_out')
  end
end

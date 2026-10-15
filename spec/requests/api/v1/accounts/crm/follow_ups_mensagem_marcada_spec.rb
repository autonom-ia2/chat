require 'rails_helper'

# #1590 — Mensagem marcada: com a flag, horário que já passou não é aceito na criação, e o motivo de uma mensagem não ter saído
# chega à tela como código (o texto cru de send_error continua fora).
RSpec.describe 'CRM follow-ups API — Mensagem marcada', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [user]) }
  let(:contact) { account.contacts.create!(name: 'Mariana', phone_number: '+5511987654321') }
  let(:conversation) { create_crm_conversation(account: account, inbox: inbox, contact: contact, assignee: user) }
  let(:template) { create_whatsapp_api_template(account: account, inbox: inbox, user: user) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, contact: contact,
                              primary_conversation: conversation, title: 'Plano anual')
  end

  def criar(due_at:, automation_mode: 'auto_send_message')
    post "/api/v1/accounts/#{account.id}/crm/follow_ups",
         params: {
           follow_up: {
             card_id: card.id, conversation_id: conversation.id, title: 'Mensagem para Mariana',
             due_at: due_at.iso8601, timezone: 'America/Sao_Paulo', automation_mode: automation_mode,
             metadata: { message_body: 'Oi, Mariana!', whatsapp_api_message_template_id: template.id }
           }
         },
         headers: auth_headers(user)
  end

  it 'sem a flag crm_mensagem_marcada, aceita mensagem automática com horário que já passou, como antes' do
    expect { criar(due_at: 10.minutes.ago) }.to change(Crm::FollowUp, :count).by(1)

    expect(response).to have_http_status(:created)
  end

  it 'recusa mensagem automática com horário que já passou, com código estável' do
    account.enable_features!('crm_mensagem_marcada')

    expect { criar(due_at: 10.minutes.ago) }.not_to change(Crm::FollowUp, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('due_at_in_the_past')
    expect(response.parsed_body['attributes']).to include('due_at')
  end

  it 'aceita a mensagem automática marcada para agora (folga de 1 minuto) e para o futuro' do
    account.enable_features!('crm_mensagem_marcada')
    criar(due_at: 20.seconds.ago)
    expect(response).to have_http_status(:created)

    criar(due_at: 2.hours.from_now)
    expect(response).to have_http_status(:created)
  end

  it 'não muda o lembrete para a equipe: horário passado continua aceito' do
    account.enable_features!('crm_mensagem_marcada')
    criar(due_at: 2.hours.ago, automation_mode: 'reminder_only')

    expect(response).to have_http_status(:created)
  end

  def follow_up_que_nao_saiu
    follow_up = account.crm_follow_ups.create!(
      card: card, conversation: conversation, title: 'Mensagem para Mariana', due_at: 1.hour.from_now, timezone: 'UTC',
      automation_mode: :auto_send_message, created_by: user,
      metadata: { 'message_body' => 'Oi', 'whatsapp_api_message_template_id' => template.id }
    )
    follow_up.update!(status: :overdue, metadata: follow_up.metadata.merge('send_error' => 'whatsapp_api_unavailable'))
    follow_up
  end

  it 'com a flag, manda o motivo da falha como código, sem o texto cru' do
    account.enable_features!('crm_mensagem_marcada')
    follow_up = follow_up_que_nao_saiu

    get "/api/v1/accounts/#{account.id}/crm/follow_ups/#{follow_up.id}", headers: auth_headers(user)

    payload = response.parsed_body['payload']
    expect(payload['send_error_code']).to eq('celular_desconectado')
    expect(payload['metadata']).not_to have_key('send_error')
  end

  it 'sem a flag, o lembrete sai como antes, sem send_error_code' do
    follow_up = follow_up_que_nao_saiu

    get "/api/v1/accounts/#{account.id}/crm/follow_ups/#{follow_up.id}", headers: auth_headers(user)

    payload = response.parsed_body['payload']
    expect(payload).not_to have_key('send_error_code')
    expect(payload['metadata']).not_to have_key('send_error')
  end
end

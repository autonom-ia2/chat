require 'rails_helper'

# #993 (PRD §6.4, B8, B1b): "vão receber" before creating the campaign — exact, each person in one
# reason only, same rules as the send.
RSpec.describe 'Journey recipient preview (#993)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:content) do
    "Nome,Celular,Email,Vencimento\n" \
      "Ana Souza,11987654321,ana@alfa.com.br,10/2026\n" \
      "Bia Lima,21987654321,bia@beta.com.br,\n" \
      "Caio Reis,31987654321,caio@gama.com.br,\n"
  end
  let(:audience) do
    saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'phone' => 1, 'email' => 2 })
  end

  def contact_named(name)
    audience.campaign_import_rows.includes(:contact).find { |row| row.contact.name == name }.contact
  end

  def preview(body, member = user)
    post "/api/v1/accounts/#{account.id}/campaign_journey/recipient_previews",
         params: { campaign_import_id: audience.id }.merge(body),
         headers: { 'api_access_token' => member.access_token.token }, as: :json
    response.parsed_body['payload']
  end

  before do
    contact_named('Bia Lima').opt_out!(source: 'manual')
  end

  it 'WhatsApp Oficial: refused and missing variable, each person once' do
    payload = preview(channel: 'whatsapp_cloud',
                      variable_bindings: { '1' => { 'source' => 'column', 'value' => 'Vencimento' } })

    expect(response).to have_http_status(:ok)
    # Bia refused AND has no Vencimento: counted only as refused.
    expect(payload).to include('total' => 3, 'receive' => 1,
                               'reasons' => { 'opted_out' => 1, 'missing_variables' => 1 },
                               'missing_by_variable' => { '1' => 1 })
  end

  it 'a default text brings the person back' do
    payload = preview(channel: 'whatsapp_cloud',
                      variable_bindings: { '1' => { 'source' => 'column', 'value' => 'Vencimento' } },
                      variable_defaults: { '1' => 'em breve' })

    expect(payload).to include('receive' => 2, 'reasons' => { 'opted_out' => 1 })
  end

  it 'WhatsApp API: tokens of the message, same rules' do
    payload = preview(channel: 'whatsapp_api', message_body: 'Oi {{contact.first_name}}, vence em {{publico.vencimento}}')

    expect(payload).to include('total' => 3, 'receive' => 1, 'reasons' => { 'opted_out' => 1, 'missing_variables' => 1 },
                               'missing_by_variable' => { 'vencimento' => 1 })
  end

  it 'SMS (#1004): same phone rule, its own switch and the message tokens' do
    payload = preview(channel: 'sms', message_body: 'Oi {{contact.first_name}}, vence {{publico.vencimento}}')
    expect(payload).to include('total' => 3, 'receive' => 0, 'reasons' => { 'channel_disabled' => 3 })

    audience.update!(channels: audience.channels.merge('sms' => { 'enabled' => true, 'count' => 3 }))
    payload = preview(channel: 'sms', message_body: 'Oi {{contact.first_name}}, vence {{publico.vencimento}}')
    expect(payload).to include('total' => 3, 'receive' => 1, 'reasons' => { 'opted_out' => 1, 'missing_variables' => 1 },
                               'missing_by_variable' => { 'vencimento' => 1 })
  end

  it 'e-mail: refused and unsubscribed are out' do
    EmailSuppression.create!(account: account, email: 'caio@gama.com.br', reason: 'unsubscribe', source: 'manual')

    payload = preview(channel: 'email')

    expect(payload).to include('total' => 3, 'receive' => 1, 'reasons' => { 'opted_out' => 1, 'unsubscribed' => 1 })
  end

  it 'a channel switched off reaches nobody' do
    audience.update!(channels: audience.channels.merge('whatsapp' => audience.channels['whatsapp'].merge('enabled' => false)))

    payload = preview(channel: 'whatsapp_cloud')

    expect(payload).to include('total' => 3, 'receive' => 0, 'reasons' => { 'channel_disabled' => 3 })
  end

  it 'a contact import (#1006) is not an audience' do
    audience.update!(options: audience.options.merge('flow' => CampaignImport::CONTACTS_FLOW))

    preview(channel: 'whatsapp_cloud')

    expect(response).to have_http_status(:not_found)
  end

  it 'refuses an unknown channel and needs campaign_manage' do
    preview(channel: 'telegram')
    expect(response).to have_http_status(:unprocessable_entity)

    agent = User.create!(name: 'Agente', email: "agente-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: agent, role: :agent,
                        custom_role: create(:custom_role, account: account, permissions: ['campaign_view']))
    preview({ channel: 'email' }, agent)
    expect(response).to have_http_status(:unauthorized)
  end
end

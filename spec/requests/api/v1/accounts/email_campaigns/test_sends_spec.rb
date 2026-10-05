require 'rails_helper'

# #999, PRD §8.9 and acceptance D8, L5, L6: "Enviar teste" works by the verified domain and by the
# inbox (direct), goes only to the logged-in user when no address is given, uses the first
# recipient as sample with an inert unsubscribe link, carries the reply inbox as Reply-To and does
# not count in the results. Senders are doubles: no real e-mail leaves.
RSpec.describe 'E-mail campaign test send (#999, D8/L6)', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, email: 'gestora@empresa.com.br') }
  let(:replies_inbox) { create(:channel_email, account: account, email: 'respostas@empresa.com.br').inbox }
  let(:campaign) do
    create(:email_campaign, account: account, status: :draft, reply_to_inbox: replies_inbox,
                            subject: 'Oi {{ nome }}', body_html: '<p>{{ empresa }}</p><a href="{{ unsubscribe_url }}">Sair</a>')
  end
  let(:delivered) { [] }

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    create(:email_campaign_recipient, email_campaign: campaign, email: 'ana@alfa.com.br', name: 'Ana Souza',
                                      custom_data: { 'empresa' => 'Alfa Corretora' })
  end

  def capturing(klass)
    sender = instance_double(klass)
    allow(sender).to receive(:deliver) { |**args| delivered << args and 'test-message' }
    allow(klass).to receive(:new).and_return(sender)
  end

  def send_test(body = {})
    post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/test_send",
         params: body, headers: admin.create_new_auth_token, as: :json
  end

  def results_snapshot
    [campaign.reload.email_campaign_recipients.count, EmailEvent.count, campaign.recipients_count, campaign.sent_count]
  end

  it 'sends by the verified domain only to the logged-in user, as the first recipient, without counting' do
    capturing(EmailCampaigns::Ses::Sender)
    before = results_snapshot

    send_test

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include('message_id' => 'test-message', 'to_email' => 'gestora@empresa.com.br')
    expect(delivered.size).to eq(1)
    mail = delivered.first
    expect(mail).to include(to: 'gestora@empresa.com.br', subject: 'Oi Ana Souza', reply_to: 'respostas@empresa.com.br')
    expect(mail[:html_body]).to include('Alfa Corretora', 'href="#"')
    expect(results_snapshot).to eq(before)
    expect(campaign.email_campaign_recipients.pluck(:status)).to eq(['pending'])
  end

  it 'sends by the inbox when the campaign sends directly (it used to answer sender_identity_missing)' do
    sender_inbox = create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox
    campaign.update!(delivery_mode: :direct_inbox, sender_inbox: sender_inbox, sender_identity: nil)
    capturing(EmailCampaigns::DirectInbox::Sender)
    before = results_snapshot

    send_test

    expect(response).to have_http_status(:ok)
    expect(EmailCampaigns::DirectInbox::Sender).to have_received(:new).with(sender_inbox)
    expect(delivered.first).to include(to: 'gestora@empresa.com.br', from_email: 'vendas@empresa.com.br',
                                       reply_to: 'respostas@empresa.com.br', subject: 'Oi Ana Souza')
    expect(delivered.first[:html_body]).to include('href="#"')
    expect(delivered.first[:headers]).to be_nil
    expect(results_snapshot).to eq(before)
  end

  it 'answers test_send_failed when the inbox cannot send, without leaking the provider error' do
    sender_inbox = create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox
    campaign.update!(delivery_mode: :direct_inbox, sender_inbox: sender_inbox, sender_identity: nil)
    sender = instance_double(EmailCampaigns::DirectInbox::Sender)
    allow(sender).to receive(:deliver).and_raise(StandardError, 'smtp secret detail')
    allow(EmailCampaigns::DirectInbox::Sender).to receive(:new).and_return(sender)

    send_test

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_failed')
  end

  # #999 review B7: 10 test sends per user and campaign in an hour.
  it 'limits test sends per user and campaign' do
    capturing(EmailCampaigns::Ses::Sender)
    Redis::Alfred.delete("email_campaign_test_send:#{admin.id}:#{campaign.id}")

    10.times { send_test }
    expect(response).to have_http_status(:ok)
    send_test

    expect(response).to have_http_status(:too_many_requests)
    expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_rate_limited')
    expect(delivered.size).to eq(10)
  ensure
    Redis::Alfred.delete("email_campaign_test_send:#{admin.id}:#{campaign.id}")
  end

  it 'refuses any address other than the logged-in user, and a campaign without a ready sender' do
    capturing(EmailCampaigns::Ses::Sender)
    send_test(to_email: 'outra@empresa.com.br')
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_only_self')
    expect(delivered).to be_empty

    send_test(to_email: 'Gestora@Empresa.com.br')
    expect(response).to have_http_status(:ok)
    expect(delivered.first[:to]).to eq('gestora@empresa.com.br')

    campaign.sender_identity.update!(status: :pending)
    send_test
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.sender_identity_missing')
  end
end

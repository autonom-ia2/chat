require 'rails_helper'

# #999, PRD §8.9 and acceptance D8, L5, L6: "Enviar teste" works by the verified domain and by the
# inbox (direct), goes to the logged-in user when no address is given, uses the first recipient as
# sample with an inert unsubscribe link, carries the reply inbox as Reply-To and does not count in
# the results. #1093 (decision of 07/10/2026): up to 5 typed addresses per test, only for who
# manages campaigns, suppressed or opted-out addresses refused. Senders are doubles: no real
# e-mail leaves.
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

  it 'refuses a campaign without a ready sender' do
    capturing(EmailCampaigns::Ses::Sender)
    campaign.sender_identity.update!(status: :pending)

    send_test

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq('email_campaign.sender_identity_missing')
    expect(delivered).to be_empty
  end

  describe 'typed addresses (#1093)' do
    after { Redis::Alfred.delete("email_campaign_test_send:#{admin.id}:#{campaign.id}") }

    it 'sends one test to each typed address, any address, without repeating one' do
      capturing(EmailCampaigns::Ses::Sender)
      before = results_snapshot

      send_test(to_emails: ['socio@outra.com.br', ' cliente@gmail.com ', 'Socio@Outra.com.br'])

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['to_emails']).to eq(['socio@outra.com.br', 'cliente@gmail.com'])
      expect(delivered.pluck(:to)).to eq(['socio@outra.com.br', 'cliente@gmail.com'])
      expect(delivered.pluck(:subject).uniq).to eq(['Oi Ana Souza'])
      expect(results_snapshot).to eq(before)
    end

    it 'keeps the single address field working, for any address' do
      capturing(EmailCampaigns::Ses::Sender)

      send_test(to_email: 'outra@empresa.com.br')

      expect(response).to have_http_status(:ok)
      expect(delivered.pluck(:to)).to eq(['outra@empresa.com.br'])
    end

    it 'refuses more than 5 addresses and sends nothing' do
      capturing(EmailCampaigns::Ses::Sender)

      send_test(to_emails: (1..6).map { |n| "pessoa#{n}@empresa.com.br" })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_too_many', 'limit' => 5)
      expect(delivered).to be_empty
    end

    it 'refuses an invalid address, says which one and sends nothing' do
      capturing(EmailCampaigns::Ses::Sender)

      send_test(to_emails: ['certo@empresa.com.br', 'errado@'])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_campaign.invalid_email', 'email' => 'errado@')
      expect(delivered).to be_empty
    end

    it 'refuses a suppressed or opted-out address with a clear code and sends nothing' do
      capturing(EmailCampaigns::Ses::Sender)
      EmailSuppression.create!(account: account, email: 'saiu@empresa.com.br', reason: 'unsubscribe', source: 'link')
      create(:contact, account: account, email: 'nao-quer@empresa.com.br', opted_out_at: Time.current)

      send_test(to_emails: ['ok@empresa.com.br', 'Saiu@Empresa.com.br'])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_suppressed', 'email' => 'saiu@empresa.com.br')

      send_test(to_emails: ['nao-quer@empresa.com.br'])
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to eq('error' => 'email_campaign.test_send_suppressed', 'email' => 'nao-quer@empresa.com.br')
      expect(delivered).to be_empty
    end

    it 'counts one send per test in the 10/hour limit, however many addresses it has' do
      capturing(EmailCampaigns::Ses::Sender)

      10.times { send_test(to_emails: ['a@empresa.com.br', 'b@empresa.com.br']) }
      expect(response).to have_http_status(:ok)
      send_test(to_emails: ['a@empresa.com.br'])

      expect(response).to have_http_status(:too_many_requests)
      expect(delivered.size).to eq(20)
    end

    it 'is only for who manages campaigns' do
      capturing(EmailCampaigns::Ses::Sender)
      agent = create(:user, account: account, role: :agent)

      post "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}/test_send",
           params: { to_emails: ['cliente@gmail.com'] }, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(delivered).to be_empty
    end
  end
end

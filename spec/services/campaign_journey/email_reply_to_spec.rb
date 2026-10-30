require 'rails_helper'

# #999, PRD §8.9 and acceptance L5: "Respostas vão para a caixa X" — the domain send, the direct
# inbox send and the test send carry that inbox's address as Reply-To, and a reply sent to it
# becomes a conversation in that inbox, with the contact who replied. No real e-mail leaves.
RSpec.describe 'E-mail campaign reply-to inbox (#999, L5)', :aggregate_failures, type: :request do
  include ActionMailbox::TestHelper

  let(:account) { create(:account) }
  let(:replies_inbox) { create(:channel_email, account: account, email: 'respostas@empresa.com.br').inbox }
  let(:contact) { create(:contact, account: account, name: 'Ana Souza', email: 'ana@alfa.com.br') }
  let(:campaign) do
    create(:email_campaign, account: account, status: :sending, reply_to_inbox: replies_inbox, reply_to: 'antigo@empresa.com.br')
  end
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, email: contact.email, contact: contact,
                                      preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end
  let(:delivered) { [] }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'shadow', 'EMAIL_REPUTATION_MODE' => 'shadow',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.org/u/synthetic')
  end

  def capturing_sender(klass)
    sender = instance_double(klass)
    allow(sender).to receive(:deliver) { |**args| delivered << args and "msg-#{delivered.size}" }
    sender
  end

  describe EmailCampaigns::ReplyTo do
    it 'prefers the reply inbox, then the typed address, then the domain reply inbox, then the sender' do
      expect(described_class.for(campaign)).to eq('respostas@empresa.com.br')

      campaign.update!(reply_to_inbox: nil)
      expect(described_class.for(campaign)).to eq('antigo@empresa.com.br')

      campaign.update!(reply_to: nil)
      campaign.sender_identity.update!(reply_to_inbox_id: replies_inbox.id)
      expect(described_class.for(campaign.reload)).to eq('respostas@empresa.com.br')

      campaign.sender_identity.update!(reply_to_inbox_id: nil)
      expect(described_class.for(campaign.reload)).to eq('sender@example.org')
    end

    # #2237: "A mesma do remetente" is the campaign's own From, not the domain's default from_email.
    it 'falls back to the campaign From, not the address saved on the verified domain' do
      campaign.sender_identity.update!(from_email: 'lucas@example.org')
      campaign.update!(reply_to_inbox: nil, reply_to: nil, from_email: 'jhuliene@example.org')

      expect(described_class.for(campaign.reload)).to eq('jhuliene@example.org')

      campaign.update!(from_email: nil)
      expect(described_class.for(campaign.reload)).to eq('lucas@example.org')
    end

    it 'refuses a reply inbox that is not an e-mail inbox of the account' do
      other = create(:channel_email).inbox
      api_inbox = create(:inbox, account: account)

      expect(campaign.update(reply_to_inbox: other)).to be(false)
      expect(campaign.errors[:reply_to_inbox_id]).to be_present
      expect(campaign.update(reply_to_inbox: api_inbox)).to be(false)
    end
  end

  it 'sends by the verified domain with the inbox as Reply-To' do
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(capturing_sender(EmailCampaigns::Ses::Sender))
    engine = EmailCampaigns::DeliveryEngine.new(campaign)
    allow(engine).to receive(:sleep)

    engine.perform

    expect(delivered.size).to eq(1)
    expect(delivered.first).to include(to: 'ana@alfa.com.br', reply_to: 'respostas@empresa.com.br')
    expect(recipient.reload.sent_at).to be_present
  end

  it 'sends by the verified domain with the campaign From as Reply-To when no reply inbox is chosen (#2237)' do
    campaign.sender_identity.update!(from_email: 'lucas@example.org')
    campaign.update!(reply_to_inbox: nil, reply_to: nil, from_email: 'jhuliene@example.org')
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(capturing_sender(EmailCampaigns::Ses::Sender))
    engine = EmailCampaigns::DeliveryEngine.new(campaign.reload)
    allow(engine).to receive(:sleep)

    engine.perform

    expect(delivered.size).to eq(1)
    expect(delivered.first).to include(from_email: 'jhuliene@example.org', reply_to: 'jhuliene@example.org')
  end

  it 'shows on the campaign the Reply-To the send will really use (#2237)' do
    admin = create(:user, account: account, role: :administrator)
    campaign.sender_identity.update!(from_email: 'lucas@example.org')
    campaign.update!(reply_to_inbox: nil, reply_to: nil, from_email: 'jhuliene@example.org')

    get "/api/v1/accounts/#{account.id}/email_campaigns/campaigns/#{campaign.id}", headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'reply_to_address')).to eq('jhuliene@example.org')
  end

  it 'uses one From chain for the send, the test send and the Reply-To (#2237)' do
    identity = campaign.sender_identity
    campaign.update!(reply_to_inbox: nil, reply_to: nil, from_email: nil)
    identity.update!(from_email: nil)

    expect(campaign.reload.sender_address).to eq("no-reply@#{identity.domain}")
    expect(EmailCampaigns::ReplyTo.for(campaign)).to eq("no-reply@#{identity.domain}")
  end

  it 'sends by the inbox (direct) with the reply inbox as Reply-To' do
    sender_inbox = create(:channel_email, account: account, email: 'vendas@empresa.com.br').inbox
    campaign.update!(delivery_mode: :direct_inbox, sender_inbox: sender_inbox, sender_identity: nil)
    sender = capturing_sender(EmailCampaigns::DirectInbox::Sender)

    EmailCampaigns::DirectInbox::RecipientSender.new(campaign, sender).deliver(recipient)

    expect(delivered.first).to include(from_email: 'vendas@empresa.com.br', reply_to: 'respostas@empresa.com.br')
    expect(delivered.first[:headers]).to include('List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click')
  end

  it 'turns the reply into a conversation of the reply inbox, with the contact who replied' do
    replies_inbox
    contact

    receive_inbound_email_from_mail(
      from: 'Ana Souza <ana@alfa.com.br>', to: 'respostas@empresa.com.br',
      subject: 'Re: Example', body: 'Quero saber mais sobre a proposta.'
    )

    conversation = replies_inbox.conversations.last
    expect(conversation).to be_present
    expect(conversation.contact).to eq(contact)
    expect(conversation.messages.incoming.last.content).to include('Quero saber mais')
  end
end

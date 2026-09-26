require 'rails_helper'

# chat#737: a campanha de e-mail não envia a quem recusou mensagens ativas. A lista vem de CSV, sem contact_id;
# a ligação é pelo e-mail com os contatos da MESMA conta. O destinatário vira suppressed.
RSpec.describe EmailCampaigns::DeliveryClaim, type: :model do
  let(:campaign) { create(:email_campaign, status: :sending) }
  let(:account) { campaign.account }
  let!(:recipient) do
    create(:email_campaign_recipient, email_campaign: campaign, email: 'ana.silva@example.org',
                                      preflight_status: 'valid', preflight_valid_until: 1.hour.from_now)
  end
  let(:sender) { instance_double(EmailCampaigns::Ses::Sender, deliver: 'accepted-synthetic') }
  let(:engine) { EmailCampaigns::DeliveryEngine.new(campaign) }

  around do |example|
    with_modified_env('EMAIL_CAMPAIGN_HYGIENE_MODE' => 'enforce', 'EMAIL_REPUTATION_MODE' => 'shadow',
                      'EMAIL_REPUTATION_PROVIDER_MONITOR' => 'false', 'EMAIL_REPUTATION_PROVIDER_BLOCK' => 'false',
                      'EMAIL_REPUTATION_AWS_ACCOUNT_ID' => '') { example.run }
  end

  before do
    allow(EmailCampaigns::Config).to receive(:enabled?).and_return(true)
    allow(EmailCampaigns::Ses::Sender).to receive(:new).and_return(sender)
    allow(EmailCampaigns::Unsubscribe::Token).to receive(:url).and_return('https://example.org/u/synthetic')
    allow(EmailCampaigns::Tracking::Injector).to receive(:new).and_return(
      instance_double(EmailCampaigns::Tracking::Injector, perform: '<p>Synthetic</p>')
    )
    allow(engine).to receive(:sleep)
  end

  it 'não envia e marca suppressed quando o contato da conta com aquele e-mail recusou' do
    create(:contact, account: account, email: 'Ana.Silva@Example.org').opt_out!(source: 'manual')

    engine.perform

    expect(sender).not_to have_received(:deliver)
    expect(recipient.reload).to be_suppressed
  end

  it 'reconfere na autorização final: quem recusa durante a renderização não recebe' do
    contact = create(:contact, account: account, email: 'ana.silva@example.org')
    allow(engine).to receive(:render) do
      contact.opt_out!(source: 'prospecting')
      { subject: 'Synthetic', body_html: '<p>Synthetic</p>' }
    end

    engine.perform

    expect(sender).not_to have_received(:deliver)
    expect(recipient.reload).to be_suppressed
  end

  it 'a recusa de outra conta não vale nesta' do
    create(:contact, account: create(:account), email: 'ana.silva@example.org').opt_out!(source: 'manual')
    create(:contact, account: account, email: 'ana.silva@example.org')

    engine.perform

    expect(sender).to have_received(:deliver).once
    expect(recipient.reload).to be_sent
  end

  it 'envia normalmente quando o contato não recusou' do
    create(:contact, account: account, email: 'ana.silva@example.org')

    engine.perform

    expect(sender).to have_received(:deliver).once
    expect(recipient.reload).to be_sent
  end

  describe EmailCampaigns::Presentation::Recipients do
    it 'mostra a recusa do contato como motivo do destinatário suprimido' do
      create(:contact, account: account, email: 'ana.silva@example.org').opt_out!(source: 'manual')
      recipient.update!(status: :suppressed)

      result = described_class.new(campaign, [recipient]).call.first

      expect(result[:suppression_reason]).to eq('opt_out')
    end

    it 'não inventa motivo para quem não recusou' do
      create(:contact, account: account, email: 'ana.silva@example.org')

      expect(described_class.new(campaign, [recipient]).call.first[:suppression_reason]).to be_nil
    end
  end
end

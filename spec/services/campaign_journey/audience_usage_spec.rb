require 'rails_helper'

# #2775: um Público "já enviado" não muda mais. A regra por tipo de campanha ligada.
RSpec.describe CampaignJourney::AudienceUsage do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:audience) do
    account.campaign_imports.create!(user: admin, status: :completed, mode: 'single_label', name: 'Lista', campaign_name: 'Lista',
                                     options: { 'flow' => CampaignImport::AUDIENCE_FLOW, 'source' => 'prospecting' })
  end

  def link(campaign)
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
  end

  it 'sem campanha ligada não trava' do
    expect(described_class.locked?(audience)).to be(false)
  end

  describe 'e-mail' do
    let(:campaign) { create(:email_campaign, account: account) }

    before { link(campaign) }

    it 'rascunho e agendada não travam' do
      expect(described_class.locked?(audience)).to be(false)
      campaign.update_columns(status: EmailCampaign.statuses[:scheduled]) # rubocop:disable Rails/SkipsModelValidations
      expect(described_class.locked?(audience)).to be(false)
    end

    it 'sending, paused e sent travam' do
      %i[sending paused sent].each do |status|
        campaign.update_columns(status: EmailCampaign.statuses[status]) # rubocop:disable Rails/SkipsModelValidations
        expect(described_class.locked?(audience)).to be(true), "status #{status}"
      end
    end

    it 'trava quando algum destinatário já tem sent_at, mesmo agendada' do
      campaign.update_columns(status: EmailCampaign.statuses[:scheduled]) # rubocop:disable Rails/SkipsModelValidations
      create(:email_campaign_recipient, email_campaign: campaign, sent_at: 1.minute.ago)

      expect(described_class.locked?(audience)).to be(true)
    end

    it 'campanha aberta (#2717) não trava quando a coluna existe' do
      campaign.update_columns(status: EmailCampaign.statuses[:sending]) # rubocop:disable Rails/SkipsModelValidations
      allow(campaign).to receive(:has_attribute?).and_call_original
      allow(campaign).to receive(:has_attribute?).with(:aberta).and_return(true)
      allow(campaign).to receive(:[]).and_call_original
      allow(campaign).to receive(:[]).with(:aberta).and_return(true)

      expect(described_class.campaign_locked?(campaign)).to be(false)
    end
  end

  describe 'WhatsApp API' do
    let(:inbox) { create_crm_whatsapp_api_inbox(account: account) }

    def api_campaign(status)
      WhatsappApiCampaign.create!(account: account, inbox: inbox, created_by: admin, title: 'Lembrete', message_body: 'Olá',
                                  audience: [{ 'type' => 'Label', 'id' => 1 }], scheduled_at: 1.hour.from_now, status: status)
    end

    it 'agendada não trava' do
      link(api_campaign(:scheduled))

      expect(described_class.locked?(audience)).to be(false)
    end

    it 'qualquer outro status trava' do
      link(api_campaign(:running))

      expect(described_class.locked?(audience)).to be(true)
    end
  end

  describe 'envio único (Campaign)' do
    let(:campaign) { create(:campaign, account: account) }

    before { link(campaign) }

    it 'active (agendada que não saiu) não trava' do
      expect(described_class.locked?(audience)).to be(false)
    end

    it 'processing e completed travam' do
      %w[processing completed].each do |status|
        campaign.update_columns(campaign_status: Campaign.campaign_statuses[status]) # rubocop:disable Rails/SkipsModelValidations
        expect(described_class.locked?(audience)).to be(true), "status #{status}"
      end
    end
  end

  it 'locked_ids responde por vários Públicos de uma vez' do
    other = account.campaign_imports.create!(user: admin, status: :completed, mode: 'single_label', name: 'Outra', campaign_name: 'Outra',
                                             options: { 'flow' => CampaignImport::AUDIENCE_FLOW })
    campaign = create(:campaign, account: account)
    campaign.update_columns(campaign_status: Campaign.campaign_statuses['completed']) # rubocop:disable Rails/SkipsModelValidations
    link(campaign)

    expect(described_class.locked_ids([audience, other])).to eq(Set[audience.id])
  end

  # Revisão do #2775, item 11: as campanhas de e-mail com destinatário enviado saem de uma consulta só, não uma por campanha.
  it 'locked_ids lê os destinatários enviados numa consulta só, com várias campanhas de e-mail' do
    audiences = Array.new(3) do |index|
      account.campaign_imports.create!(user: admin, status: :completed, mode: 'single_label', name: "L#{index}", campaign_name: "L#{index}",
                                       options: { 'flow' => CampaignImport::AUDIENCE_FLOW })
    end
    identity = create(:email_sender_identity, account: account)
    audiences.each do |item|
      campaign = create(:email_campaign, account: account, sender_identity: identity)
      CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: item)
    end
    sent = CampaignAudienceLink.find_by(campaign_import: audiences.last).campaign
    create(:email_campaign_recipient, email_campaign: sent, sent_at: Time.current)

    queries = []
    callback = ->(*, payload) { queries << payload[:sql] if payload[:sql].include?('email_campaign_recipients') }
    ids = ActiveSupport::Notifications.subscribed(callback, 'sql.active_record') { described_class.locked_ids(audiences) }

    expect(ids).to eq(Set[audiences.last.id])
    expect(queries.size).to eq(1)
  end
end

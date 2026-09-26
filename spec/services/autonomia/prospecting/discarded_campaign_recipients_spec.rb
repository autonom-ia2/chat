require 'rails_helper'

# Descarte tira da campanha em andamento (decisão de 26/09): a campanha da API do WhatsApp resolve o público quando
# começa e guarda os destinatários. Lead descartado depois disso sai dos pendentes da campanha que recebeu o segmento da
# lista dele, com o motivo 'discarded', no job que o descarte já enfileira. A campanha não termina com falhas por isso.
RSpec.describe Autonomia::Prospecting::DiscardedCampaignRecipients do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:base_label) { account.labels.create!(title: 'base_campanha') }
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Selecao') }

  around do |example|
    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'true') { example.run }
  end

  def add_lead(key, phone, target_list: list)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "discarded-campaign-#{key}", name: "Lead #{key}", phone: phone,
      country: 'BR', status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } }
    )
    target_list.list_leads.create!(account: account, lead: lead)
    lead
  end

  def running_campaign_from(segment_list)
    campaign = create_whatsapp_api_campaign(account: account, user: admin, inbox: inbox, label: base_label)
    Autonomia::Prospecting::CampaignSegmentBuilder.new(list: segment_list, user: admin, campaign_id: campaign.id,
                                                       campaign_type: 'whatsapp_api').perform
    WhatsappApiCampaigns::AudienceResolver.new(campaign.reload).perform
    campaign.update!(status: :running, started_at: Time.current)
    campaign
  end

  def discard(*leads)
    perform_enqueued_jobs(only: Autonomia::Prospecting::SegmentRefusalSyncJob) do
      Autonomia::Prospecting::LeadDiscard.new(account: account, lead_ids: leads.map(&:id), reason: 'Sem interesse').perform
    end
  end

  def recipient_of(campaign, lead)
    campaign.whatsapp_api_campaign_recipients.find_by!(contact_id: lead.reload.contact_id)
  end

  it 'campanha em andamento com pendente: o lead descartado depois sai dos pendentes com o motivo' do
    kept = add_lead(1, '+5531999970001')
    discarded = add_lead(2, '+5531999970002')
    campaign = running_campaign_from(list)
    expect(recipient_of(campaign, discarded)).to be_pending

    discard(discarded)

    recipient = recipient_of(campaign, discarded)
    expect(recipient).to be_cancelled
    expect(recipient.last_error_message).to eq('discarded')
    expect(recipient.cancelled_at).to be_present
    expect(recipient_of(campaign, kept)).to be_pending
    expect(campaign.reload.cancelled_count).to eq(1)
  end

  it 'o descartado não recebe e a campanha termina concluída, sem falhas' do
    allow(WhatsappApiCampaigns::Config).to receive(:enabled?).and_return(true)
    kept = add_lead(1, '+5531999970001')
    discarded = add_lead(2, '+5531999970002')
    campaign = running_campaign_from(list)
    discard(discarded)

    3.times { WhatsappApiCampaigns::DeliveryEngine.new(campaign).perform }

    expect(recipient_of(campaign, discarded).message_id).to be_nil
    expect(recipient_of(campaign, kept)).to be_sent
    campaign.reload
    expect(campaign).to be_completed
    expect(campaign.failed_count).to eq(0)
    expect(campaign.discarded_count).to eq(1)
  end

  it 'contato que outro lead elegível da mesma lista ainda alcança continua pendente' do
    discarded = add_lead(1, '+5531999970011')
    add_lead(2, '+5531999970011')
    campaign = running_campaign_from(list)

    discard(discarded)

    expect(recipient_of(campaign, discarded)).to be_pending
  end

  it 'não mexe em campanha que não recebeu o segmento da lista do lead nem em destinatário já enviado' do
    other_list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Outra')
    discarded = add_lead(1, '+5531999970021')
    add_lead(2, '+5531999970022', target_list: other_list)
    campaign = running_campaign_from(list)
    other_campaign = create_whatsapp_api_campaign(account: account, user: admin, inbox: inbox, label: base_label)
    discarded.reload.contact.add_labels(base_label.title)
    WhatsappApiCampaigns::AudienceResolver.new(other_campaign).perform
    other_campaign.update!(status: :running)
    recipient_of(campaign, discarded).update!(status: :sent, sent_at: Time.current)

    discard(discarded)

    expect(recipient_of(campaign, discarded)).to be_sent
    expect(recipient_of(other_campaign, discarded)).to be_pending
  end

  it 'lead que voltou atrás antes do job não sai da campanha' do
    lead = add_lead(1, '+5531999970031')
    campaign = running_campaign_from(list)
    lead.update!(status: :discarded, discard_reason: 'Engano')
    lead.update!(status: :ready_for_campaign)

    described_class.new(account: account).perform([lead])

    expect(recipient_of(campaign, lead)).to be_pending
  end
end

require 'rails_helper'

# #1329: the WhatsApp Oficial campaign checks its template before going out. Before this, a template
# paused or changed after the campaign was created went out anyway: every contact got Meta's error
# and the campaign ended "completed" (reproduced on main 98b391477f: 2 sends with components [],
# 2 failed recipients, campaign completed).
RSpec.describe CampaignPauses::WhatsappDispatchGate, :aggregate_failures do
  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:template) { CampaignJourneyHelpers::JOURNEY_TEMPLATE.deep_dup }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular\nAna Souza,11987654321\nBia Lima,21987654321\n")
  end
  let(:campaign) do
    campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params,
                                 message: 'Olá {{1}}')
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience, variable_bindings: {}, variable_defaults: {})
    campaign
  end

  def dispatch
    Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
  end

  it 'is the outermost perform, so the journey and Enterprise steps (opt-out, destination) still run after it' do
    ancestors = Whatsapp::OneoffCampaignService.ancestors
    expect(ancestors.index(described_class)).to be < ancestors.index(CampaignJourney::AudienceContacts)
    expect(ancestors.index(described_class)).to be < ancestors.index(Enterprise::Whatsapp::OneoffCampaignService)
    expect(ancestors.index(described_class)).to be < ancestors.index(CampaignJourney::WhatsappOneoffRecipients)
    expect(Campaign.ancestors.first(3)).to include(CampaignPauses::TriggerGate)
  end

  describe 'a template that no longer matches' do
    it 'sends to no one and pauses the campaign by the template when Meta says it is paused (the #1329 bug)' do
      sent = stub_graph_messages
      stub_meta_template_lookup([template.merge('status' => 'PAUSED')])
      campaign.update!(campaign_status: :processing) # as Campaign#trigger! leaves it

      dispatch

      expect(sent).to be_empty
      expect(CampaignRecipient.where(campaign: campaign)).to be_empty
      expect(campaign.reload).to be_active
      pause = CampaignPause.open_for(campaign)
      expect(pause).to have_attributes(source: 'template', reason_code: 'template_not_approved', account_id: account.id)
      expect(pause.details).to include('status' => 'PAUSED', 'template_name' => 'renovacao', 'lookup_source' => 'meta')
    end

    it 'pauses when the template was edited after the campaign was created (variables changed)' do
      sent = stub_graph_messages
      stub_meta_template_lookup([template.merge('components' => [{ 'type' => 'BODY', 'text' => 'Oi {{nome}}' }])])

      dispatch

      expect(sent).to be_empty
      expect(CampaignPause.open_for(campaign).reason_code).to eq('template_structure_changed')
    end

    it 'pauses by the system with template_unverifiable when neither Meta nor the cache can be read' do
      sent = stub_graph_messages
      stub_meta_template_lookup(503)
      channel.update_columns(message_templates: [], message_templates_last_updated: Time.current) # rubocop:disable Rails/SkipsModelValidations

      dispatch

      expect(sent).to be_empty
      expect(CampaignPause.open_for(campaign)).to have_attributes(source: 'system', reason_code: 'template_unverifiable')
    end

    it 'pauses by the system, never sends blind nor stays processing, when the check itself breaks' do
      sent = stub_graph_messages
      allow(Whatsapp::Templates::DispatchCheck).to receive(:new).and_raise(NoMethodError)
      campaign.update!(campaign_status: :processing)

      dispatch

      expect(sent).to be_empty
      expect(campaign.reload).to be_active
      expect(CampaignPause.open_for(campaign)).to have_attributes(source: 'system', reason_code: 'template_unverifiable')
    end

    it 'keeps a single open pause when the campaign is dispatched again' do
      stub_graph_messages
      stub_meta_template_lookup([template.merge('status' => 'PAUSED')])

      2.times { dispatch }

      expect(CampaignPause.where(pausable: campaign).count).to eq(1)
    end
  end

  describe 'a template that still matches' do
    it 'sends as before, after one Meta lookup' do
      sent = stub_graph_messages
      lookups = stub_meta_template_lookup([template])

      dispatch

      expect(lookups.size).to eq(1)
      expect(sent.pluck('to')).to contain_exactly('+5511987654321', '+5521987654321')
      expect(campaign.reload).to be_completed
      expect(CampaignPause.where(pausable: campaign)).to be_empty
    end

    it 'keeps the opt-out (chat#737): who refuses during the send is skipped' do
      bia = audience.campaign_import_rows.find_by(row_number: 3).contact
      sent = stub_graph_messages(on_send: ->(_body) { bia.opt_out!(source: 'manual') })
      stub_meta_template_lookup([template])

      dispatch

      expect(sent.pluck('to')).to eq(['+5511987654321'])
      recipient = CampaignRecipient.find_by!(campaign: campaign, contact: bia)
      expect(recipient).to be_skipped
      expect(recipient.error_message).to eq('opted_out')
    end

    it 'keeps the BSUID destination for a label campaign contact without phone' do
      label = create(:label, account: account)
      label_campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [{ type: 'Label', id: label.id }],
                                         template_params: journey_template_params, message: 'Olá')
      contact = create(:contact, account: account, phone_number: nil)
      contact.update_labels([label.title])
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: 'IN.2081978709342942')
      stub_meta_template_lookup([template])
      sent = []
      stub_request(:post, ->(uri) { uri.path.end_with?('/messages') }).to_return do |request|
        sent << JSON.parse(request.body)
        { status: 200, headers: { 'Content-Type' => 'application/json' }, body: { messages: [{ id: 'wamid.b' }] }.to_json }
      end

      Whatsapp::OneoffCampaignService.new(campaign: label_campaign).perform

      expect(sent.size).to eq(1)
      expect(sent.first.to_json).to include('IN.2081978709342942')
    end
  end

  describe 'trigger and resume' do
    before { stub_graph_messages }

    it 'does not fire a paused campaign: it stays active and nothing is sent' do
      CampaignPauses::Pauser.new(campaign, source: 'template', reason_code: 'template_not_approved').perform
      lookups = stub_meta_template_lookup([template])

      campaign.trigger!

      expect(campaign.reload).to be_active
      expect(lookups).to be_empty
      expect(CampaignRecipient.where(campaign: campaign)).to be_empty
    end

    it 'fires again on resume and sends once when the template is back' do
      stub_meta_template_lookup([template.merge('status' => 'PAUSED')])
      campaign.trigger!
      pause = CampaignPause.open_for(campaign)
      stub_meta_template_lookup([template])

      perform_enqueued_jobs { CampaignPauses::Resumer.new(pause, resumed_by: user).perform }

      expect(pause.reload).to have_attributes(resumed_by_id: user.id)
      expect(pause.resumed_at).to be_present
      expect(CampaignRecipient.where(campaign: campaign).pluck(:status)).to eq(%w[sent sent])
      expect(campaign.reload).to be_completed

      perform_enqueued_jobs { campaign.trigger! }
      expect(CampaignRecipient.where(campaign: campaign).count).to eq(2)
      expect { CampaignPauses::Resumer.new(pause).perform }.to raise_error(CampaignPauses::Resumer::Error, 'pause_not_open')
    end

    it 'opens a new pause on resume when the template still does not match' do
      stub_meta_template_lookup([template.merge('status' => 'PAUSED')])
      campaign.trigger!
      first = CampaignPause.open_for(campaign)

      perform_enqueued_jobs { CampaignPauses::Resumer.new(first).perform }

      expect(CampaignPause.open_for(campaign)).to be_present
      expect(CampaignPause.open_for(campaign).id).not_to eq(first.id)
      expect(CampaignRecipient.where(campaign: campaign)).to be_empty
    end

    it 'never fires a completed campaign again on resume' do
      campaign.update!(campaign_status: :completed)
      pause = CampaignPause.create!(account: account, pausable: campaign, source: 'manual', reason_code: 'manual_pause', paused_at: Time.current)
      lookups = stub_meta_template_lookup([template])

      perform_enqueued_jobs { CampaignPauses::Resumer.new(pause).perform }

      expect(lookups).to be_empty
      expect(CampaignRecipient.where(campaign: campaign)).to be_empty
    end

    it 'refuses to resume a campaign that already has messages sent, and keeps the pause' do
      contact = audience.campaign_import_rows.first.contact
      CampaignRecipient.create!(account: account, campaign: campaign, inbox: channel.inbox, contact: contact, status: :sent)
      pause = CampaignPauses::Pauser.new(campaign, source: 'manual', reason_code: 'manual_pause').perform

      expect { CampaignPauses::Resumer.new(pause).perform }.to raise_error(CampaignPauses::Resumer::Error, 'campaign_already_sent')
      expect(pause.reload).to be_open
      expect(enqueued_jobs.pluck(:job)).not_to include(Campaigns::TriggerOneoffCampaignJob)
    end
  end
end

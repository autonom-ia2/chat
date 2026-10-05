require 'rails_helper'

# #1005 J5/J6: PATCH /campaign_imports/:id/channels and F2/N4: deleting an audience.
RSpec.describe 'Audience channels and deletion (#1005)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular,Empresa\nAna,11987654321,Alfa\nBia,21987654321,Beta\n",
                   mapping: { 'name' => 0, 'phone' => 1, 'company' => 2 })
  end

  def headers_for(member = user)
    { 'api_access_token' => member.access_token.token }
  end

  def patch_channels(body, as: user)
    patch "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}/channels", params: body, headers: headers_for(as), as: :json
  end

  def agent_with(permissions)
    agent = User.create!(name: 'Agente', email: "agente-#{SecureRandom.hex(4)}@example.com", password: 'Passw0rd!23', confirmed_at: Time.current)
    AccountUser.create!(account: account, user: agent, role: :agent, custom_role: create(:custom_role, account: account, permissions: permissions))
    agent
  end

  def linked_campaign(status:, title: 'Renovação outubro')
    channel = journey_cloud_channel(account)
    campaign = create(:campaign, account: account, inbox: channel.inbox, title: title, audience: [], template_params: journey_template_params)
    campaign.update_columns(campaign_status: Campaign.campaign_statuses[status]) # rubocop:disable Rails/SkipsModelValidations
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
    campaign
  end

  describe 'PATCH channels' do
    it 'turns a channel off and on again' do
      patch_channels({ whatsapp: false })
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'channels', 'whatsapp')).to eq('enabled' => false, 'count' => 2)
      expect(audience.reload.channels['whatsapp']).to eq('enabled' => false, 'count' => 2)

      patch_channels({ whatsapp: true })
      expect(audience.reload.channels['whatsapp']).to eq('enabled' => true, 'count' => 2)
    end

    # Coordinator decision 3: a channel a scheduled or running campaign sends through stays on.
    it 'refuses to turn off a channel used by a campaign that has not finished, and allows it once it has' do
      campaign = linked_campaign(status: :active)

      patch_channels({ whatsapp: false })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'audience_in_use',
                                              'campaigns' => [{ 'title' => 'Renovação outubro', 'display_id' => campaign.display_id }])
      expect(audience.reload.channels.dig('whatsapp', 'enabled')).to be(true)

      patch_channels({ email: false })
      expect(response).to have_http_status(:ok)

      campaign.update_columns(campaign_status: Campaign.campaign_statuses[:completed]) # rubocop:disable Rails/SkipsModelValidations
      patch_channels({ whatsapp: false })
      expect(response).to have_http_status(:ok)
      expect(audience.reload.channels.dig('whatsapp', 'enabled')).to be(false)
    end

    # J6: a channel without data cannot be turned on.
    it 'refuses to turn on a channel without data' do
      patch_channels({ email: true })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('campaign_import.channel_without_data')
      expect(audience.reload.channels['email']).to eq('enabled' => false, 'count' => 0)
    end

    it 'refuses unknown values and old campaign bases' do
      patch_channels({ whatsapp: 'talvez' })
      expect(response.parsed_body['error']).to eq('campaign_import.invalid_channels_choice')

      old = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n")
      patch "/api/v1/accounts/#{account.id}/campaign_imports/#{old.id}/channels", params: { whatsapp: false }, headers: headers_for, as: :json
      expect(response.parsed_body['error']).to eq('campaign_import.not_an_audience')
    end

    # A4: campaign_view cannot change who an audience reaches.
    it 'answers 401 to campaign_view only' do
      patch_channels({ whatsapp: false }, as: agent_with(%w[campaign_view]))

      expect(response).to have_http_status(:unauthorized)
      expect(audience.reload.channels.dig('whatsapp', 'enabled')).to be(true)
    end
  end

  # F2/N4: "Excluir público" deletes only the list.
  describe 'DELETE an audience' do
    it 'deletes the list and keeps contacts, companies, conversations and campaign results' do
      account.enable_features!(:companies)
      channel = journey_cloud_channel(account)
      contact = audience.campaign_import_rows.order(:row_number).first.contact
      conversation = create(:conversation, account: account, inbox: channel.inbox, contact: contact)
      campaign = create(:campaign, account: account, inbox: channel.inbox, audience: [], template_params: journey_template_params)
      link = CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
      stub_graph_messages
      Whatsapp::OneoffCampaignService.new(campaign: campaign).perform
      contacts_before = account.contacts.count
      companies_before = Company.where(account: account).count

      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for

      expect(response).to have_http_status(:no_content)
      expect(CampaignImport.exists?(audience.id)).to be(false)
      expect(CampaignImportRow.where(campaign_import_id: audience.id)).to be_empty
      expect(account.contacts.count).to eq(contacts_before)
      expect(Company.where(account: account).count).to eq(companies_before)
      expect(companies_before).to eq(2)
      expect(conversation.reload).to be_present
      expect(campaign.reload).to be_completed
      expect(CampaignRecipient.where(campaign: campaign).pluck(:status)).to eq(%w[sent sent])
      expect(link.reload.campaign_import_id).to be_nil
    end

    # Coordinator decision 2: an audience a scheduled or running campaign still sends to cannot be deleted.
    it 'refuses to delete an audience used by a campaign that has not finished, listing it' do
      scheduled = linked_campaign(status: :active, title: 'Agendada')
      linked_campaign(status: :completed, title: 'Concluída')

      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('error' => 'campaign_import.audience_in_use', 'code' => 'audience_in_use')
      expect(response.parsed_body['campaigns']).to eq([{ 'title' => 'Agendada', 'display_id' => scheduled.display_id }])
      expect(CampaignImport.exists?(audience.id)).to be(true)

      scheduled.update_columns(campaign_status: Campaign.campaign_statuses[:processing]) # rubocop:disable Rails/SkipsModelValidations
      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for
      expect(response.parsed_body['code']).to eq('audience_in_use')
    end

    it 'keeps refusing to delete an audience while it is being saved, and answers 401 to campaign_view only' do
      audience.update!(status: :importing)
      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for
      expect(response.parsed_body['error']).to eq('campaign_import.delete_not_available')

      audience.update!(status: :completed)
      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for(agent_with(%w[campaign_view]))
      expect(response).to have_http_status(:unauthorized)
      expect(CampaignImport.exists?(audience.id)).to be(true)
    end

    # AudienceUsage: a campaign scheduled more than 3 days ago is no longer picked by the scheduler.
    it 'does not count as in use a campaign the scheduler no longer picks' do
      campaign = linked_campaign(status: :active)
      campaign.update_columns(scheduled_at: 4.days.ago) # rubocop:disable Rails/SkipsModelValidations

      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}", headers: headers_for

      expect(response).to have_http_status(:no_content)
    end

    # B3: undoing labels of an import an unfinished campaign uses is blocked the same way.
    it 'refuses undo_labels while an unfinished campaign uses the import' do
      linked_campaign(status: :active)

      post "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}/undo_labels", headers: headers_for

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('audience_in_use')
      expect(audience.reload).to be_completed
    end

    it 'keeps the old rule for campaign bases: no deletion after contacts were imported' do
      old = create_campaign_import(account: account, user: user, content: "nome,telefone\nAna,11987654321\n", batch_count: 1)
      CampaignImports::Validator.new(old).perform
      old.reload.update!(status: :queued)
      CampaignImports::Importer.new(old.reload).perform

      delete "/api/v1/accounts/#{account.id}/campaign_imports/#{old.id}", headers: headers_for

      expect(response.parsed_body['error']).to eq('campaign_import.delete_not_available')
    end
  end
end

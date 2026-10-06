require 'rails_helper'

# #1005 review fixes on POST campaign_journey/campaigns (A1, M1, M2, B1/B2).
RSpec.describe 'Campaign journey campaigns API, review fixes (#1005)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true') { example.run }
  end

  let(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:channel) { journey_cloud_channel(account) }
  let(:audience) do
    saved_audience(account: account, user: user, content: "Nome,Celular,Email,Vencimento\nAna,11987654321,,10/2026\nBia,,bia@b.com.br,\n",
                   mapping: { 'name' => 0, 'phone' => 1, 'email' => 2 })
  end
  let(:bindings) do
    { '1' => { source: 'contact', value: 'first_name' }, '2' => { source: 'column', value: 'Vencimento' },
      '3' => { source: 'fixed', value: 'Equipe' } }
  end

  def create_campaign(campaign_import_id: audience.id, **campaign)
    body = {
      campaign_import_id: campaign_import_id, channel: 'whatsapp_cloud',
      campaign: { title: 'Renovação', inbox_id: channel.inbox.id, scheduled_at: nil,
                  template_params: journey_template_params, variable_bindings: bindings, variable_defaults: {} }.merge(campaign)
    }
    post "/api/v1/accounts/#{account.id}/campaign_journey/campaigns", params: body, headers: { 'api_access_token' => user.access_token.token },
                                                                      as: :json
  end

  # A1: the channel count after saving and recipients_count follow the same rule.
  it 'counts only contacts that still have the phone of their row, the same number the audience channel shows' do
    account.contacts.create!(name: 'Ana antiga', email: 'ana@alfa.com.br', phone_number: '+5541999990000')
    content = "Nome,Celular,Email\nAna,11987654321,ana@alfa.com.br\nCaio,31987654321,\n"
    other = saved_audience(account: account, user: user, content: content, mapping: { 'name' => 0, 'phone' => 1, 'email' => 2 })
    expect(other.channels['whatsapp']).to eq('enabled' => true, 'count' => 1)

    create_campaign(campaign_import_id: other.id, variable_bindings: bindings.merge('2' => { source: 'fixed', value: 'x' }))

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['recipients_count']).to eq(1)
  end

  describe 'M1: variables against the approved template' do
    it 'refuses a binding for a variable the template does not have' do
      create_campaign(variable_bindings: bindings.merge('7' => { source: 'fixed', value: 'x' }))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'invalid_variable_bindings')
      expect(response.parsed_body['details']).to include('unknown' => ['7'])
    end

    it 'refuses a template variable without binding or default, and accepts a default alone' do
      create_campaign(variable_bindings: bindings.except('3'))
      expect(response.parsed_body).to include('code' => 'invalid_variable_bindings')
      expect(response.parsed_body['details']).to include('missing' => ['3'])

      create_campaign(variable_bindings: bindings.except('3'), variable_defaults: { '3' => 'Equipe' })
      expect(response).to have_http_status(:ok)
    end

    it 'refuses a template that is not approved in the inbox' do
      create_campaign(template_params: journey_template_params.merge('name' => 'nao_existe'))

      expect(response.parsed_body['code']).to eq('template_not_found')
    end
  end

  describe 'M2' do
    it 'refuses a schedule in the past' do
      create_campaign(scheduled_at: 2.hours.ago.iso8601)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('invalid_schedule')
    end

    it 'refuses when the whatsapp_campaign feature is off' do
      channel
      account.disable_features!(:whatsapp_campaign)

      create_campaign

      expect(response.parsed_body['code']).to eq('feature_disabled')
    end
  end

  describe 'B1/B2: the audience changes while the campaign is created' do
    it 'revalidates the audience under lock' do
      audience
      allow_any_instance_of(CampaignImport).to receive(:lock!) do |campaign_import| # rubocop:disable RSpec/AnyInstance
        campaign_import.update_columns(status: CampaignImport.statuses[:importing]) # rubocop:disable Rails/SkipsModelValidations
        campaign_import.reload
      end

      create_campaign

      expect(response.parsed_body['code']).to eq('audience_not_ready')
      expect(account.campaigns.count).to eq(0)
    end

    it 'answers audience_not_ready when the audience is deleted at the same time' do
      audience
      allow(CampaignAudienceLink).to receive(:create!).and_raise(ActiveRecord::InvalidForeignKey, 'fk')

      create_campaign

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('audience_not_ready')
      expect(account.campaigns.count).to eq(0)
    end
  end
end

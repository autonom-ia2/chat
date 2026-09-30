require 'rails_helper'

RSpec.describe 'Email campaign template workspace', :aggregate_failures, type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:headers) { admin.create_new_auth_token }
  let(:path) { "/api/v1/accounts/#{account.id}/email_campaigns/templates" }
  let(:catalog_entry) { EmailCampaigns::TemplateCatalog.entries.first }
  let!(:global_template) do
    EmailCampaignTemplate.create!(
      account: nil,
      name: catalog_entry.fetch('name'),
      category: catalog_entry.fetch('category'),
      body_mjml: EmailCampaigns::TemplateCatalog.body(catalog_entry),
      body_html: EmailCampaigns::TemplateCatalog::ROOT.join(catalog_entry.fetch('path')).sub_ext('.html').read
    )
  end
  let!(:account_template) do
    EmailCampaignTemplate.create!(account: account, name: 'Minha campanha', category: 'meus-modelos',
                                  body_mjml: '<mjml><mj-body><mj-text>Account</mj-text></mj-body></mjml>',
                                  body_html: '<html>Account</html>')
  end

  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true' do
      example.run
    end
  end

  it 'lists shared and account templates without leaking a foreign account' do
    foreign = create(:account)
    foreign_template = EmailCampaignTemplate.create!(account: foreign, name: 'Foreign template', category: 'private',
                                                     body_mjml: '<mjml />', body_html: '<html>Foreign</html>')

    get path, headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      hash_including('id' => global_template.id, 'account_id' => nil, 'catalog_key' => catalog_entry.fetch('key')),
      hash_including('id' => account_template.id, 'account_id' => account.id, 'catalog_key' => nil)
    )
    expect(response.parsed_body).not_to include(hash_including('id' => foreign_template.id))
    expect(response.parsed_body).to all(satisfy { |template| template.exclude?('body_mjml') && template.exclude?('body_html') })
  end

  it 'allows reading a shared template and keeps the global record read-only' do
    get "#{path}/#{global_template.id}", headers: headers, as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      'id' => global_template.id,
      'account_id' => nil,
      'body_mjml' => global_template.body_mjml,
      'body_html' => global_template.body_html
    )

    delete "#{path}/#{global_template.id}", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
    expect(global_template.reload).to be_persisted
  end

  it 'keeps the account write scope isolated and allows an administrator to create and remove own templates' do
    payload = {
      email_template: {
        name: 'Novo modelo da conta',
        category: 'meus-modelos',
        body_mjml: '<mjml><mj-body><mj-text>Novo</mj-text></mj-body></mjml>',
        body_html: '<html>Novo</html>'
      }
    }

    post path, params: payload, headers: headers, as: :json

    expect(response).to have_http_status(:created)
    created = EmailCampaignTemplate.find(response.parsed_body.fetch('id'))
    expect(created.account_id).to eq(account.id)

    delete "#{path}/#{created.id}", headers: headers, as: :json

    expect(response).to have_http_status(:no_content)
    expect(EmailCampaignTemplate.where(id: created.id)).to be_empty
  end

  it 'denies template workspace access to an ordinary agent' do
    agent = create(:user, account: account, role: :agent)

    get path, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:unauthorized)
  end

  it 'does not show a template belonging to another account' do
    foreign = create(:account)
    foreign_template = EmailCampaignTemplate.create!(account: foreign, name: 'Private foreign template', category: 'private',
                                                     body_mjml: '<mjml />', body_html: '<html>Private</html>')

    get "#{path}/#{foreign_template.id}", headers: headers, as: :json

    expect(response).to have_http_status(:not_found)
  end
end

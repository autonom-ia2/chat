require 'rails_helper'

# #2772 (ContactImports::ImportacaoAntigaFechada): com a importação nova ligada, a importação antiga do Chatwoot, que
# sobrescreve contato existente, fecha também para o pedido direto à API.
RSpec.describe 'Importação antiga de contatos', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/import" }
  let(:file) { fixture_file_upload(Rails.root.join('spec/assets/contacts.csv'), 'text/csv') }
  let(:new_import_on) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

  def import_contacts
    post url, headers: admin.create_new_auth_token, params: { import_file: file }
  end

  it 'refuses the legacy import when the new import is on, without creating a data import' do
    with_modified_env(new_import_on) { import_contacts }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('contact_imports.legacy_import_closed'))
    expect(account.data_imports.count).to eq(0)
  end

  it 'keeps the permission check first when the new import is on' do
    agent = create(:user, account: account, role: :agent)

    with_modified_env(new_import_on) do
      post url, headers: agent.create_new_auth_token, params: { import_file: file }
    end

    expect(response).to have_http_status(:unauthorized)
  end

  it 'keeps the legacy import when only the journey is on' do
    with_modified_env('CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'false') { import_contacts }

    expect(response).to have_http_status(:success)
    expect(account.data_imports.count).to eq(1)
  end

  it 'keeps the legacy import when the new import is off' do
    with_modified_env('CAMPAIGN_JOURNEY_ENABLED' => 'false', 'CAMPAIGN_IMPORT_ENABLED' => 'false') { import_contacts }

    expect(response).to have_http_status(:success)
    expect(account.data_imports.count).to eq(1)
  end
end

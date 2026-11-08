require 'rails_helper'

# #2332: "Baixar lista" in the audience panel — who the audience holds, as an Excel file, under the same rules as the
# contacts the panel lists (#2277).
RSpec.describe 'Campaign import people sheet (#2332)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CAMPAIGN_JOURNEY_ENABLED: 'true', CAMPAIGN_IMPORT_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account).tap { |conta| conta.enable_features!('campanhas_publico_por_conversa') } }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def headers(user = admin)
    { 'api_access_token' => user.access_token.token }
  end

  def with_role(permissions)
    create(:user, account: account, role: :agent).tap do |user|
      role = create(:custom_role, account: account, permissions: permissions)
      user.account_users.find_by(account: account).update!(custom_role: role)
    end
  end

  def sheet_path(audience)
    "/api/v1/accounts/#{account.id}/campaign_imports/#{audience.id}/people_sheet"
  end

  def sheet_rows(body)
    file = Tempfile.new(['publico', '.xlsx'])
    file.binmode
    file.write(body)
    file.flush
    sheet = Roo::Excelx.new(file.path).sheet(0)
    (1..sheet.last_row).map { |line| sheet.row(line) }
  ensure
    file&.close!
  end

  def import_row(audience, contact, extra_values: {}, company_name: nil)
    audience.campaign_import_rows.create!(row_number: audience.campaign_import_rows.count + 2,
                                          status: 'imported', contact: contact, extra_values: extra_values,
                                          company_name: company_name)
  end

  it 'gives the people of a spreadsheet audience as an Excel file, with the extra columns and nothing as a formula' do
    audience = create_audience_import(account: account, user: admin, content: "nome,telefone\nAna,11987654321\n")
    audience.update!(name: 'Clientes Março', extra_columns: %w[Cidade name])
    bia = create(:contact, account: account, name: 'Bia Flávia', phone_number: '+5521987654321', email: 'bia@example.com')
    ana = create(:contact, account: account, name: '=HYPERLINK("x")', phone_number: '+5511987654321')
    import_row(audience, bia, extra_values: { 'Cidade' => 'São Paulo', 'name' => 'Bia' }, company_name: 'Alfa')
    import_row(audience, ana)
    import_row(audience, bia)
    import_row(audience, create(:contact, account: account, name: 'Apagado')).contact.destroy!

    get sheet_path(audience), headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Type']).to include('spreadsheetml.sheet')
    expect(response.headers['Content-Disposition']).to include('attachment', 'clientes-marco.xlsx')
    expect(sheet_rows(response.body)).to eq([
                                              ['Name', 'Phone', 'E-mail', 'Company', 'Cidade', 'name (2)'],
                                              ['=HYPERLINK("x")', '+5511987654321', nil, nil, nil, nil],
                                              ['Bia Flávia', '+5521987654321', 'bia@example.com', 'Alfa', 'São Paulo', 'Bia']
                                            ])
  end

  it 'downloads the people of an old campaign base import too, as its panel lists them' do
    old = create_campaign_import(account: account, user: admin, content: "nome,telefone\nAna,11987654321\n")
    import_row(old, create(:contact, account: account, name: 'Ana', phone_number: '+5511987654321'))

    get sheet_path(old), headers: headers

    expect(response).to have_http_status(:ok)
    expect(sheet_rows(response.body).drop(1)).to eq([['Ana', '+5511987654321', nil, nil]])
  end

  it 'refuses an agent without campaign_manage' do
    audience = create_audience_import(account: account, user: admin, content: "nome,telefone\nAna,11987654321\n")

    get sheet_path(audience), headers: headers(create(:user, account: account, role: :agent))

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'an audience from the conversations (#2277)' do
    let(:path) { "/api/v1/accounts/#{account.id}/campaign_journey/conversation_audiences" }
    let(:inbox_a) { create(:inbox, account: account) }
    let(:inbox_b) { create(:inbox, account: account) }
    let(:audience) do
      search = ConversationAudienceSearch.create!(account: account, user: admin, request: 'quem cotou', period: '30d', status: 'done')
      ids = [['Bruno', inbox_b, '+5511987654322'], ['Ana', inbox_a, '+5511987654321']].map do |name, inbox, phone|
        contact = create(:contact, account: account, name: name, phone_number: phone)
        ConversationAudiencePerson.create!(search: search, contact: contact, group: 'certeza',
                                           conversation: create(:conversation, account: account, inbox: inbox, contact: contact)).id
      end
      post "#{path}/#{search.id}/save", params: { name: 'Reclamaram', person_ids: ids }, headers: headers, as: :json
      account.campaign_imports.find(response.parsed_body['id'])
    end

    it 'needs contact_view, and gives only the people whose conversation the viewer can open' do
      without, reader = [%w[campaign_manage conversation_view], %w[campaign_manage conversation_view contact_view]].map do |keys|
        with_role(keys).tap { |user| create(:inbox_member, user: user, inbox: inbox_a) }
      end

      get sheet_path(audience), headers: headers(without)
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['error']).to eq('campaign_import.contacts_hidden')

      get sheet_path(audience), headers: headers(reader)
      expect(sheet_rows(response.body).drop(1).map(&:first)).to eq(['Ana'])

      get sheet_path(audience), headers: headers
      expect(sheet_rows(response.body).drop(1).map(&:first)).to eq(%w[Ana Bruno])
    end
  end
end

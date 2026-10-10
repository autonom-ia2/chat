require 'rails_helper'

# "Marcar como cliente" (#1144): o painel do contato marca e desfaz pela rota própria. A primeira data fica.
RSpec.describe 'Contact customer API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account, contact_type: :lead) }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/customer" }

  it 'exige usuário autenticado' do
    post url, as: :json

    expect(response).to have_http_status(:unauthorized)
    expect(contact.reload).to be_lead
  end

  it 'marca como cliente com a data de hoje e devolve o contato' do
    freeze_time do
      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(contact.reload).to be_customer
      expect(response.parsed_body.dig('payload', 'contact_type')).to eq('customer')
      expect(response.parsed_body.dig('payload', 'customer_since')).to eq(Time.current.to_i)
    end
  end

  it 'não troca a data de quem já é cliente' do
    since = 3.months.ago.beginning_of_day
    contact.update!(contact_type: :customer, customer_since: since)

    post url, headers: agent.create_new_auth_token, as: :json

    expect(contact.reload.customer_since).to eq(since)
  end

  it 'desfaz: volta a lead e perde a data' do
    contact.update!(contact_type: :customer, customer_since: 1.day.ago)

    delete url, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(contact.reload).to be_lead
    expect(contact.customer_since).to be_nil
  end

  it 'não alcança contato de outra conta' do
    other_contact = create(:contact, account: create(:account))

    post "/api/v1/accounts/#{account.id}/contacts/#{other_contact.id}/customer", headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(other_contact.reload).not_to be_customer
  end
end

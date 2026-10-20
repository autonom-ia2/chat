require 'rails_helper'

# #1157 — o módulo Contatos (lista, ativos, filtros, empresas) exige contact_view numa função
# personalizada. O contato aberto pela conversa ou pelo card e a busca usada para iniciar
# conversa continuam abertos. Administrador e agente sem função ficam como antes.
RSpec.describe 'Contacts module read (Enterprise policy)', type: :request do
  let(:account) { create(:account) }
  let(:contact) { create(:contact, account: account, name: 'Lead Teste') }
  let(:user) { create(:user) }
  let(:filter_payload) do
    { payload: [{ attribute_key: 'name', filter_operator: 'contains', values: ['Lead'], query_operator: nil }] }
  end

  def seat(permissions: nil, role: :agent)
    custom_role = permissions && create(:custom_role, account: account, permissions: permissions)
    create(:account_user, account: account, user: user, role: role, custom_role: custom_role)
  end

  def list_statuses
    headers = user.create_new_auth_token
    base = "/api/v1/accounts/#{account.id}"
    get "#{base}/contacts", headers: headers, as: :json
    index = response.status
    get "#{base}/contacts/active", headers: headers, as: :json
    active = response.status
    post "#{base}/contacts/filter", params: filter_payload, headers: headers, as: :json
    filter = response.status
    get "#{base}/companies", headers: headers, as: :json
    [index, active, filter, response.status]
  end

  def contextual_statuses
    headers = user.create_new_auth_token
    base = "/api/v1/accounts/#{account.id}"
    get "#{base}/contacts/#{contact.id}", headers: headers, as: :json
    show = response.status
    get "#{base}/contacts/search", params: { q: 'Lead' }, headers: headers, as: :json
    [show, response.status]
  end

  before { account.enable_features!('custom_roles', 'companies') }

  it 'refuses the module lists to a custom role without contact keys' do
    seat(permissions: %w[conversation_manage])

    expect(list_statuses).to eq([401, 401, 401, 401])
    expect(contextual_statuses).to eq([200, 200])
  end

  it 'allows the module lists with contact_view' do
    seat(permissions: %w[contact_view])

    expect(list_statuses).to eq([200, 200, 200, 200])
  end

  it 'allows the module lists with contact_manage (manage implies view)' do
    seat(permissions: %w[contact_manage])

    expect(list_statuses).to eq([200, 200, 200, 200])
  end

  it 'keeps a plain agent unchanged' do
    seat

    expect(list_statuses).to eq([200, 200, 200, 200])
  end
end

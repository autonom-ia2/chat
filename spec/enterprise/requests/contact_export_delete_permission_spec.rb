require 'rails_helper'

# Funções personalizadas, lote 5a (#1845): exportar a base sai de `contact_manage` para `contact_export`, e excluir
# contato ou empresa ganha a chave `contact_delete`. Agente sem cargo continua sem exportar e sem excluir.
RSpec.describe 'Exportar e excluir contatos por cargo', type: :request do
  let(:account) { create(:account) }
  let(:base) { "/api/v1/accounts/#{account.id}" }

  def pessoa_com(permissions)
    user = create(:user, account: account, role: :agent)
    role = CustomRole.create!(account: account, name: "Cargo #{SecureRandom.hex(4)}", permissions: permissions)
    AccountUser.find_by(account: account, user: user).update!(custom_role: role)
    user.create_new_auth_token
  end

  describe 'exportar' do
    it 'recusa quem só edita contatos' do
      post "#{base}/contacts/export", headers: pessoa_com(%w[contact_manage]), as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'aceita quem tem contact_export' do
      post "#{base}/contacts/export", headers: pessoa_com(%w[contact_view contact_export]), as: :json
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'excluir contato' do
    let(:contact) { create(:contact, account: account) }

    it 'recusa quem só edita contatos' do
      delete "#{base}/contacts/#{contact.id}", headers: pessoa_com(%w[contact_manage]), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(Contact.exists?(contact.id)).to be(true)
    end

    it 'aceita quem tem contact_delete' do
      delete "#{base}/contacts/#{contact.id}", headers: pessoa_com(%w[contact_view contact_delete]), as: :json
      expect(response).to have_http_status(:success)
      expect(Contact.exists?(contact.id)).to be(false)
    end

    it 'recusa o agente sem cargo' do
      agente = create(:user, account: account, role: :agent)
      delete "#{base}/contacts/#{contact.id}", headers: agente.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it 'libera a exclusão em massa para quem tem contact_delete' do
      params = { type: 'Contact', ids: [contact.id], action_name: 'delete' }
      post "#{base}/bulk_actions", params: params, headers: pessoa_com(%w[contact_view contact_delete]), as: :json
      expect(response).to have_http_status(:success)

      post "#{base}/bulk_actions", params: params, headers: pessoa_com(%w[contact_manage]), as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'excluir empresa' do
    let(:company) { create(:company, account: account) }

    before { account.enable_features!(:companies) }

    it 'recusa quem só edita contatos e aceita quem tem contact_delete' do
      delete "#{base}/companies/#{company.id}", headers: pessoa_com(%w[contact_manage]), as: :json
      expect(response).to have_http_status(:unauthorized)

      delete "#{base}/companies/#{company.id}", headers: pessoa_com(%w[contact_view contact_delete]), as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end

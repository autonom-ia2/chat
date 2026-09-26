require 'rails_helper'

# Recusa manual de mensagens ativas (chat#713): o painel do contato marca e desfaz pela rota própria, nunca pelo PATCH
# comum. Quem pode editar o contato pode marcar e desfazer; a marca é da conta do contato.
RSpec.describe 'Contact opt-out API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contact) { create(:contact, account: account) }
  let(:url) { "/api/v1/accounts/#{account.id}/contacts/#{contact.id}/opt_out" }

  describe 'POST /api/v1/accounts/:account_id/contacts/:contact_id/opt_out' do
    it 'exige usuário autenticado' do
      post url, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(contact.reload).not_to be_opted_out
    end

    it 'marca a recusa manual com quem marcou e devolve o contato com a marca' do
      freeze_time do
        post url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:ok)
        contact.reload
        expect(contact).to be_opted_out
        expect(contact.opt_out_source).to eq('manual')
        expect(contact.opted_out_by_id).to eq(agent.id)
        payload = response.parsed_body['payload']
        expect(payload['id']).to eq(contact.id)
        expect(payload['opted_out_at']).to eq(Time.current.to_i)
        expect(payload['opt_out_source']).to eq('manual')
      end
    end

    it 'não troca a recusa que já existia por outra origem' do
      contact.opt_out!(source: 'email_unsubscribe')

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(contact.reload.opt_out_source).to eq('email_unsubscribe')
      expect(contact.opted_out_by_id).to be_nil
    end

    it 'não alcança contato de outra conta' do
      other_contact = create(:contact, account: create(:account))

      post "/api/v1/accounts/#{account.id}/contacts/#{other_contact.id}/opt_out", headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:not_found)
      expect(other_contact.reload).not_to be_opted_out
    end

    it 'recusa quem não é da conta' do
      outsider = create(:user, account: create(:account), role: :administrator)

      post url, headers: outsider.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(contact.reload).not_to be_opted_out
    end

    it 'marca mesmo com e-mail antigo fora do formato' do
      contact.update_columns(email: 'nao-e-email') # rubocop:disable Rails/SkipsModelValidations

      post url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(contact.reload).to be_opted_out
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/contacts/:contact_id/opt_out' do
    it 'desfaz a recusa, de qualquer origem, e devolve o contato sem a marca' do
      contact.opt_out!(source: 'prospecting')

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      contact.reload
      expect(contact).not_to be_opted_out
      expect(contact.opt_out_source).to be_nil
      payload = response.parsed_body['payload']
      expect(payload['opted_out_at']).to be_nil
      expect(payload['opt_out_source']).to be_nil
    end

    it 'sem recusa não muda nada' do
      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(contact.reload).not_to be_opted_out
    end

    it 'exige usuário autenticado' do
      contact.opt_out!(source: 'manual')

      delete url, as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(contact.reload).to be_opted_out
    end
  end
end

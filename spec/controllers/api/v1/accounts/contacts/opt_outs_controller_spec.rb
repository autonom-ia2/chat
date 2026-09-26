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
    include ActiveJob::TestHelper

    def unsubscribe_email!(email)
      EmailCampaigns::SuppressionRegistry.new(account: account, email: email)
                                         .block!(reason: 'unsubscribe', source: 'link', event_key: "unsubscribe:#{email}")
    end

    it 'desfaz a recusa manual e devolve o contato sem a marca' do
      contact.opt_out!(source: 'manual', by: agent)

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      contact.reload
      expect(contact).not_to be_opted_out
      expect(contact.opt_out_source).to be_nil
      expect(contact.opted_out_by_id).to be_nil
      payload = response.parsed_body['payload']
      expect(payload['opted_out_at']).to be_nil
      expect(payload['opt_out_source']).to be_nil
    end

    it 'não desfaz a recusa da Prospecção: ela sai pelo status do lead' do
      contact.opt_out!(source: 'prospecting')

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to be_present
      expect(contact.reload).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
    end

    it 'não desfaz a recusa do descadastro de e-mail, e editar o contato depois não muda a marca' do
      contact.update!(email: 'ana@example.com')
      unsubscribe_email!('ana@example.com')
      expect(contact.reload.opt_out_source).to eq('email_unsubscribe')

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      perform_enqueued_jobs(only: Contacts::OptOutInheritanceJob) { contact.reload.update!(phone_number: '+5511988887777') }
      expect(contact.reload).to be_opted_out
      expect(contact.opt_out_source).to eq('email_unsubscribe')
    end

    it 'desfazer a manual com o e-mail descadastrado deixa a recusa com a origem do e-mail, sem sumir e voltar' do
      contact.update!(email: 'ana@example.com')
      contact.opt_out!(source: 'manual', by: agent)
      unsubscribe_email!('ana@example.com')
      expect(contact.reload.opt_out_source).to eq('manual')

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['payload']['opt_out_source']).to eq('email_unsubscribe')
      perform_enqueued_jobs(only: Contacts::OptOutInheritanceJob) { contact.reload.update!(phone_number: '+5511988887777') }
      expect(contact.reload).to be_opted_out
      expect(contact.opt_out_source).to eq('email_unsubscribe')
      expect(contact.opted_out_by_id).to be_nil
    end

    it 'desfazer a manual e depois editar telefone e e-mail não re-marca' do
      Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'places/outro',
                                           name: 'Outra', phone: '+5511900001111', status: :no_consent)
      unsubscribe_email!('outra@example.com')
      contact.opt_out!(source: 'manual', by: agent)

      delete url, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:ok)
      perform_enqueued_jobs(only: Contacts::OptOutInheritanceJob) do
        contact.reload.update!(phone_number: '+5511988887777', email: 'nova@example.com')
      end
      expect(contact.reload).not_to be_opted_out
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

  # A recusa é decisão de quem atende o contato: token de integração do CRM (RestrictIntegrationTokenToCrm, que nega
  # por padrão fora do CRM) e token de agent bot (BOT_ACCESSIBLE_ENDPOINTS) não marcam nem desfazem.
  describe 'tokens de API' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def api_headers(token)
      { api_access_token: token }
    end

    context 'with token de integração do CRM' do
      let(:token) do
        skip 'Crm::IntegrationToken is EE-only in this fork' unless defined?(Crm::IntegrationToken)

        Crm::IntegrationToken.create!(account: account, created_by: admin, name: 'n8n', scopes: ['crm_admin']).access_token.token
      end

      it 'POST recebe 401 e não marca' do
        post url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(contact.reload).not_to be_opted_out
      end

      it 'DELETE recebe 401 e não desfaz' do
        contact.opt_out!(source: 'manual', by: admin)

        delete url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(contact.reload.opt_out_source).to eq('manual')
      end
    end

    context 'with token de agent bot' do
      let(:token) { create(:agent_bot, account: account).access_token.token }

      it 'POST recebe 401 e não marca' do
        post url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(contact.reload).not_to be_opted_out
      end

      it 'DELETE recebe 401 e não desfaz' do
        contact.opt_out!(source: 'manual', by: admin)

        delete url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(contact.reload.opt_out_source).to eq('manual')
      end
    end

    context 'with token de usuário' do
      let(:token) { agent.access_token.token }

      it 'POST marca a recusa manual' do
        post url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:ok)
        expect(contact.reload.opt_out_source).to eq('manual')
        expect(contact.opted_out_by_id).to eq(agent.id)
      end

      it 'DELETE desfaz a recusa manual' do
        contact.opt_out!(source: 'manual', by: agent)

        delete url, headers: api_headers(token), as: :json

        expect(response).to have_http_status(:ok)
        expect(contact.reload).not_to be_opted_out
      end
    end
  end
end

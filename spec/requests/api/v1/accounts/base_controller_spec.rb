require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::BaseController', type: :request do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let!(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) { create(:user, account: account, role: :agent) }

  before do
    create(:inbox_member, inbox: inbox, user: agent)
  end

  context 'when agent bot belongs to the account' do
    let(:agent_bot) { create(:agent_bot, account: account) }

    it 'allows assignments via API' do
      post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
           headers: { api_access_token: agent_bot.access_token.token },
           params: { assignee_id: agent.id },
           as: :json

      expect(response).to have_http_status(:success)
    end
  end

  context 'when agent bot belongs to another account' do
    let(:other_account) { create(:account) }
    let(:external_bot) { create(:agent_bot, account: other_account) }

    it 'rejects assignment' do
      post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
           headers: { api_access_token: external_bot.access_token.token },
           params: { assignee_id: agent.id },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'when agent bot is global' do
    let(:global_bot) { create(:agent_bot, account: nil) }

    it 'rejects requests without inbox mapping' do
      post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
           headers: { api_access_token: global_bot.access_token.token },
           params: { assignee_id: agent.id },
           as: :json

      expect(response).to have_http_status(:unauthorized)
    end

    it 'allows requests when inbox mapping exists' do
      create(:agent_bot_inbox, agent_bot: global_bot, inbox: inbox)

      post api_v1_account_conversation_assignments_url(account_id: account.id, conversation_id: conversation.display_id),
           headers: { api_access_token: global_bot.access_token.token },
           params: { assignee_id: agent.id },
           as: :json

      expect(response).to have_http_status(:success)
    end
  end

  # #2110: o `rescue_from` roda por fora do `around_action` do idioma; sem reabrir o idioma, o 422 saía em inglês.
  describe 'idioma do erro que sai por rescue_from' do
    let(:admin) { create(:user, account: account, role: :administrator) }

    def criar_resposta_pronta_vazia
      post "/api/v1/accounts/#{account.id}/canned_responses",
           params: { canned_response: { short_code: 'oi', content: '' } },
           headers: admin.create_new_auth_token, as: :json
    end

    it 'sai no idioma da conta' do
      account.update!(locale: 'pt_BR')

      criar_resposta_pronta_vazia

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['message']).to eq('Content não pode ficar em branco')
    end

    it 'sai no idioma da pessoa, mesmo com a conta em inglês' do
      account.update!(locale: 'en')
      admin.update!(ui_settings: { 'locale' => 'pt_BR' })

      criar_resposta_pronta_vazia

      expect(response.parsed_body['message']).to eq('Content não pode ficar em branco')
    end

    it 'cada pedido no seu idioma, e o idioma do processo volta ao padrão depois de cada um' do
      account.update!(locale: 'pt_BR')
      criar_resposta_pronta_vazia
      expect(response.parsed_body['message']).to eq('Content não pode ficar em branco')
      expect(I18n.locale).to eq(I18n.default_locale)

      account.update!(locale: 'en')
      criar_resposta_pronta_vazia
      expect(response.parsed_body['message']).to eq("Content can't be blank")
      expect(I18n.locale).to eq(I18n.default_locale)
    end
  end
end

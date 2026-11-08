require 'rails_helper'

# #1969 (lote 10 do épico #1784): financial_view vê os custos da conta em dinheiro (uso de IA e a tela da autorização
# de cobranças da Meta); financial_manage liga e desliga essa autorização. Plano e faturas seguem só do administrador.
# Fica em spec/enterprise: a metade de função personalizada do permission_granted? é EE.
RSpec.describe 'Financial permission (#1969)', :aggregate_failures, type: :request do
  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true') { example.run }
  end

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }

  def agent_with(permissions)
    user = create(:user)
    create(:account_user, account: account, user: user, role: :agent,
                          custom_role: create(:custom_role, account: account, permissions: permissions))
    user
  end

  describe 'AI usage values' do
    let(:path) { "/api/v1/accounts/#{account.id}/crm/ai_usage" }

    before do
      allow(Crm::Ai::ExchangeRate).to receive(:current).and_return(rate: BigDecimal('5.00'), rate_unavailable: false)
      create(:crm_ai_usage_event, account: account, feature: 'agente_resposta', model: 'gpt-5.4')
    end

    it 'shows usage without money to who sees CRM reports but not the costs' do
      get path, headers: auth_headers(agent_with(%w[crm_view_reports]))

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['com_valores']).to be(false)
      expect(payload['totals']).to eq('usage_count' => 1)
      expect(payload['time_series'].first).to include('usage_count' => 1)
      expect(payload['spend_by_resource'].first).to include('usage_count' => 1)
      expect(payload).not_to have_key('exchange_rate')
      expect(response.body).not_to include('cost_usd', 'cost_brl', 'period_spend', 'cache_savings')
    end

    it 'shows the money with financial_view' do
      get path, headers: auth_headers(agent_with(%w[crm_view_reports financial_view]))

      payload = response.parsed_body['payload']
      expect(payload['com_valores']).to be(true)
      expect(payload['totals']).to include('period_spend')
      expect(payload['history']['rows'].first).to include('cost_usd', 'cost_brl')
    end

    it 'keeps the cost columns out of the CSV without financial_view' do
      get "#{path}/export", headers: auth_headers(agent_with(%w[crm_view_reports]))
      expect(response.body.lines.first).not_to include('Custo')

      get "#{path}/export", headers: auth_headers(agent_with(%w[crm_view_reports financial_view]))
      expect(response.body.lines.first).to include('Custo USD', 'Custo BRL')
    end
  end

  describe 'AI usage live push' do
    before do
      broadcasts
      allow(ActionCable.server).to receive(:broadcast) { |stream, message| broadcasts[stream] = message }
    end

    def broadcasts
      @broadcasts ||= {}
    end

    it 'sends the cost only to who has financial_view' do
      account_admin = admin
      reports_only = agent_with(%w[crm_view_reports])
      with_money = agent_with(%w[crm_view_reports financial_view])

      Crm::Ai::UsageBroadcaster.broadcast(build(:crm_ai_usage_event, account: account, feature: 'agente_resposta', model: 'gpt-5.4'))

      expect(broadcasts[reports_only.pubsub_token][:data]).not_to have_key(:cost_usd)
      expect(broadcasts[with_money.pubsub_token][:data]).to have_key(:cost_usd)
      expect(broadcasts[account_admin.pubsub_token][:data]).to have_key(:cost_usd)
    end
  end

  describe 'Meta charge authorization' do
    let(:path) { "/api/v1/accounts/#{account.id}/whatsapp_template_consent" }

    before { account.enable_features!('whatsapp_templates_journey') }

    def turn_on(user)
      post path, params: { operacao: 'ligar', marcas: %w[utility], versao_aviso: Whatsapp::Templates::AvisoDeConsentimento::VERSAO },
                 headers: auth_headers(user), as: :json
    end

    it 'lets financial_view see it but not change it' do
      viewer = agent_with(%w[financial_view])

      get path, headers: auth_headers(viewer), as: :json
      expect(response).to have_http_status(:ok)

      turn_on(viewer)
      expect(response).to have_http_status(:forbidden)
      expect(WhatsappTemplateConsent.count).to eq(0)
    end

    it 'lets financial_manage turn it on, and records who did it' do
      manager = agent_with(%w[financial_manage])

      turn_on(manager)

      expect(response).to have_http_status(:ok)
      expect(WhatsappTemplateConsent.last.user_id).to eq(manager.id)
    end

    it 'keeps who only manages templates out of the switch' do
      templates = agent_with(%w[whatsapp_templates_manage])

      get path, headers: auth_headers(templates), as: :json
      expect(response).to have_http_status(:ok)

      turn_on(templates)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'handing out the keys' do
    it 'refuses a role with a financial key to who manages people without grant_above_own' do
      hr = agent_with(%w[people_manage financial_view])
      finance_role = create(:custom_role, account: account, permissions: %w[financial_view])

      post "/api/v1/accounts/#{account.id}/agents",
           params: { name: 'Bia', email: 'bia@loja.com.br', role: 'agent', custom_role_id: finance_role.id },
           headers: auth_headers(hr), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(User.from_email('bia@loja.com.br')).to be_nil
    end
  end
end

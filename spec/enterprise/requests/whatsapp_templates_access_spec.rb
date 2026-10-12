require 'rails_helper'

# Modelos do WhatsApp (#1330) com função personalizada: `whatsapp_templates_view` vê, `whatsapp_templates_manage` altera
# (e vê). "Onde está em uso" só lista follow-up de card que a pessoa vê (acesso por funil, #1148); o resto vira
# `uso_oculto: true`, sem número, e bloqueia apagar e alterar.
RSpec.describe 'Modelos do WhatsApp com função personalizada', type: :request do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false,
                              message_templates: [])
  end
  let(:inbox) { channel.inbox }
  let(:base) { "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_templates" }
  let(:template) do
    { 'id' => '11', 'name' => 'retorno', 'language' => 'pt_BR', 'status' => 'APPROVED', 'category' => 'UTILITY',
      'components' => [{ 'type' => 'BODY', 'text' => 'Olá {{1}}, tudo certo?' }] }
  end

  before do
    channel.update_columns(message_templates: [template]) # rubocop:disable Rails/SkipsModelValidations
    account.enable_features!('whatsapp_templates_journey')
  end

  def role_user(*permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def call(user, verb, path, params = {})
    public_send(verb, path, params: params, headers: user.create_new_auth_token, as: :json)
  end

  it 'aceita as duas chaves novas na função' do
    expect(CustomRole::PERMISSIONS).to include('whatsapp_templates_view', 'whatsapp_templates_manage')
  end

  it 'ver: lista e "onde está em uso", mas não altera' do
    viewer = role_user('whatsapp_templates_view')

    call(viewer, :get, base)
    expect(response).to have_http_status(:ok)
    call(viewer, :get, "#{base}/11/usage")
    expect(response).to have_http_status(:ok)
    call(viewer, :delete, "#{base}/11")
    expect(response).to have_http_status(:unauthorized)
    call(viewer, :post, base, { template: { name: 'x' } })
    expect(response).to have_http_status(:unauthorized)
  end

  it 'alterar implica ver' do
    manager = role_user('whatsapp_templates_manage')

    call(manager, :get, base)

    expect(response).to have_http_status(:ok)
    expect(WhatsappTemplatePolicy.new({ user: manager, account: account,
                                        account_user: manager.account_users.find_by(account: account) }, nil).destroy?).to be(true)
  end

  it 'com whatsapp_templates_manage mas sem a flag da conta, apagar dá 404 sem chamar a Meta' do
    account.disable_features!('whatsapp_templates_journey')

    call(role_user('whatsapp_templates_manage'), :delete, "#{base}/11")

    expect(response).to have_http_status(:not_found)
    expect(a_request(:any, ->(uri) { uri.host == 'graph.facebook.com' })).not_to have_been_made
  end

  it 'campaign_manage sozinha não abre os modelos' do
    call(role_user('campaign_manage'), :get, base)

    expect(response).to have_http_status(:unauthorized)
  end

  describe 'uso em funil que a pessoa não vê' do
    let(:manager) { role_user('whatsapp_templates_manage', 'crm_view') }
    let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
    let(:sinistro) { create_crm_pipeline(account: account, user: admin, name: 'Sinistro') }

    before do
      inbox.add_members([manager.id])
      access = Crm::InboxAgentAccess.create!(account: account, inbox: inbox, user: manager, all_pipelines: false, triage: false)
      access.agent_pipelines.create!(account: account, pipeline: vendas.first)
    end

    def follow_up_in((pipeline, stage), title)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, inbox: inbox, title: title)
      Crm::FollowUp.create!(account: account, card: card, inbox: inbox, title: title, due_at: 1.day.from_now, status: :pending,
                            metadata: { 'template_name' => 'retorno', 'template_language' => 'pt_BR' })
    end

    it 'lista só o follow-up do funil dela e marca o resto como uso oculto, sem número' do
      follow_up_in(vendas, 'Retorno Vendas')
      follow_up_in(sinistro, 'Retorno Sinistro')

      call(manager, :get, "#{base}/11/usage")

      body = response.parsed_body
      expect(body['follow_ups'].pluck('title')).to eq(['Retorno Vendas'])
      expect(body['uso_oculto']).to be(true)
      expect(body.to_json).not_to include('Sinistro')
    end

    it 'com uso oculto, apagar é bloqueado com "em uso onde você não tem acesso"' do
      follow_up_in(sinistro, 'Retorno Sinistro')

      call(manager, :delete, "#{base}/11")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('in_use_hidden')
      expect(response.parsed_body.dig('usage', 'follow_ups')).to eq([])
    end

    it 'o administrador vê tudo' do
      follow_up_in(sinistro, 'Retorno Sinistro')

      call(admin, :get, "#{base}/11/usage")

      expect(response.parsed_body['follow_ups'].pluck('title')).to eq(['Retorno Sinistro'])
      expect(response.parsed_body['uso_oculto']).to be(false)
    end

    it 'campanha agendada sem campaign_view conta como uso oculto' do
      create(:campaign, account: account, inbox: inbox, title: 'Segredo', message: 'x', campaign_type: :one_off,
                        scheduled_at: 1.day.from_now, template_params: { 'name' => 'retorno', 'language' => 'pt_BR' })

      call(manager, :get, "#{base}/11/usage")

      expect(response.parsed_body['campaigns']).to eq([])
      expect(response.parsed_body['uso_oculto']).to be(true)
      expect(response.body).not_to include('Segredo')
    end

    # #1332: campanha parada pelo modelo que a pessoa não vê. Alterar passa (a conferência do disparo protege ao
    # retomar); apagar continua barrado como uso oculto, sem o nome.
    it 'campanha parada sem campaign_view: alterar passa, apagar fica barrado como uso oculto' do
      campaign = create(:campaign, account: account, inbox: inbox, title: 'Segredo', message: 'x', campaign_type: :one_off,
                                   scheduled_at: 1.hour.ago, template_params: { 'name' => 'retorno', 'language' => 'pt_BR' })
      CampaignPauses::Pauser.new(campaign, source: 'template', reason_code: 'template_not_approved',
                                           details: { template_name: 'retorno', status: 'PAUSED' }).perform

      call(manager, :get, "#{base}/11/usage")
      expect(response.parsed_body).to include('uso_oculto' => true, 'blocks_change' => false, 'campaigns' => [])

      call(manager, :delete, "#{base}/11")
      expect(response.parsed_body['error']).to eq('in_use_hidden')
      expect(response.body).not_to include('Segredo')
    end
  end
end

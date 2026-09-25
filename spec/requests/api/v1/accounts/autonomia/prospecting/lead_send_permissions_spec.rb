require 'rails_helper'

# Permissões do envio ao CRM e da campanha pela prospecção (#680): quem só tem a prospecção não cria card nem mexe na
# audiência de campanha. Cada envio passa pela permissão do módulo que ele altera, como no próprio CRM e nas campanhas.
RSpec.describe 'Autonomia prospecting send permissions', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  # Campanha de SMS só agendada: nada é enviado no teste.
  let(:campaign) do
    create(:campaign, account: account, inbox: create(:channel_sms, account: account).inbox, audience: [], scheduled_at: 1.day.from_now)
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-perm-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-000#{index}", country: 'BR',
      metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => "+55 31 99999-000#{index}" } }
    )
  end

  describe 'envio ao CRM' do
    it 'papel só com a prospecção não cria card em lote (403) e nada é gravado' do
      post "#{base_url}/leads/crm_cards", params: { lead_ids: [create_lead(1).id], pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.forbidden')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.crm_send.errors.forbidden'))
      expect(account.crm_cards.count).to eq(0)
    end

    it 'papel só com a prospecção não cria card individual (403)' do
      lead = create_lead(1)

      post "#{base_url}/leads/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
                                                    headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(account.crm_cards.count).to eq(0)
      expect(lead.reload.contact_id).to be_nil
    end

    it 'papel com a prospecção e com crm_manage_cards envia' do
      post "#{base_url}/leads/crm_cards", params: { lead_ids: [create_lead(1).id], pipeline_id: pipeline.id, stage_id: stage.id },
                                          headers: auth_headers(agent_with(%w[prospecting_manage crm_manage_cards])), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'created').size).to eq(1)
    end
  end

  describe 'campanha' do
    it 'seleção com campaign_id sem campaign_manage responde 403 e a audiência não muda' do
      post "#{base_url}/leads/campaign_segment",
           params: { lead_ids: [create_lead(1).id], campaign_id: campaign.display_id, segment_name: 'Sel' },
           headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.campaign.forbidden')
      expect(campaign.reload.audience).to eq([])
      expect(account.autonomia_prospecting_lists.count).to eq(0)
    end

    it 'lista com campaign_id sem campaign_manage responde 403 e a audiência não muda' do
      list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista')
      list.list_leads.create!(account: account, lead: create_lead(1))

      post "#{base_url}/lists/#{list.id}/campaign_segment", params: { campaign_segment: { campaign_id: campaign.display_id } },
                                                            headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(campaign.reload.audience).to eq([])
    end

    # A campanha one-off decide quem recebe pelas etiquetas na hora do envio. Reaplicar a etiqueta de uma lista que já
    # está na audiência, mesmo sem campaign_id, aumenta quem recebe: também exige campaign_manage.
    it 'lista já ligada a uma campanha, sem campaign_id e sem campaign_manage, responde 403 e ninguém ganha a etiqueta' do
      list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista')
      list.list_leads.create!(account: account, lead: create_lead(1).tap { |lead| lead.update!(status: 'ready_for_campaign') })
      post "#{base_url}/lists/#{list.id}/campaign_segment",
           params: { campaign_segment: { campaign_id: campaign.display_id, segment_name: 'Lista' } },
           headers: auth_headers(admin), as: :json
      expect(response).to have_http_status(:created)
      label_title = response.parsed_body.dig('payload', 'segment', 'label', 'title')
      tagged_before = Contact.where(account: account).tagged_with(label_title).count

      list.list_leads.create!(account: account, lead: create_lead(2).tap { |lead| lead.update!(status: 'ready_for_campaign') })
      post "#{base_url}/lists/#{list.id}/campaign_segment", params: { campaign_segment: { segment_name: 'Lista' } },
                                                            headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.campaign.forbidden')
      expect(Contact.where(account: account).tagged_with(label_title).count).to eq(tagged_before)
    end

    it 'lista que não está em campanha nenhuma continua podendo gerar o segmento só com a prospecção' do
      list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista solta')
      list.list_leads.create!(account: account, lead: create_lead(3).tap { |lead| lead.update!(status: 'ready_for_campaign') })

      post "#{base_url}/lists/#{list.id}/campaign_segment", params: { campaign_segment: { segment_name: 'Lista solta' } },
                                                            headers: auth_headers(agent_with(['prospecting_manage'])), as: :json

      expect(response).to have_http_status(:created)
    end

    it 'com campaign_manage a seleção entra na campanha' do
      post "#{base_url}/leads/campaign_segment",
           params: { lead_ids: [create_lead(1).id], campaign_id: campaign.display_id, segment_name: 'Sel' },
           headers: auth_headers(agent_with(%w[prospecting_manage campaign_manage])), as: :json

      expect(response).to have_http_status(:created)
      expect(campaign.reload.audience.size).to eq(1)
    end
  end
end

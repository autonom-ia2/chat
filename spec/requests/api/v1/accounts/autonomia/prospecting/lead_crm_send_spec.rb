require 'rails_helper'

# Envio ao CRM e campanha a partir da seleção de leads (#680, frente B): formatos do contrato com a tela.
RSpec.describe 'Autonomia prospecting send to CRM and campaign from selection', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def create_lead(index, target_account: account, **attributes)
    Autonomia::Prospecting::Lead.create!(
      {
        account: target_account, provider: 'mock', provider_place_id: "place-#{target_account.id}-#{index}",
        name: "Empresa #{index}", phone: format('+55 31 9%<n>04d-0000', n: 1000 + index), country: 'BR'
      }.merge(attributes)
    )
  end

  def send_to_crm(lead_ids, user: admin)
    post "#{base_url}/crm_cards", params: { lead_ids: lead_ids, pipeline_id: pipeline.id, stage_id: stage.id },
                                  headers: auth_headers(user), as: :json
  end

  describe 'POST leads/crm_cards' do
    it 'devolve criados, já existentes e falhas por lead' do
      leads = Array.new(3) { |index| create_lead(index) }
      foreign = create_lead(9, target_account: create(:account))
      send_to_crm([leads.first.id])

      send_to_crm(leads.map(&:id) + [foreign.id])

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['created'].map { |row| row['lead_id'] }).to match_array(leads.drop(1).map(&:id))
      expect(payload['created'].first.keys).to match_array(%w[lead_id card_id contact_id company_id])
      expect(payload['existing']).to eq([{ 'lead_id' => leads.first.id, 'card_id' => leads.first.reload.crm_card_id }])
      expect(payload['failed']).to eq([{ 'lead_id' => foreign.id, 'reason_code' => 'not_found',
                                         'message' => I18n.t('autonomia.prospecting.crm_send.failures.not_found') }])
      expect(foreign.reload.crm_card_id).to be_nil
    end

    it 'recusa mais de 30 leads com 422' do
      send_to_crm((1..31).to_a)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.too_many_leads')
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.crm_send.errors.too_many_leads', max: 30))
    end

    it 'recusa lista vazia com 422' do
      send_to_crm([])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.crm_send.no_leads')
    end

    it 'funil ou estágio de outra conta é 404 e nada é criado' do
      lead = create_lead(1)
      other = create(:account)
      _other_pipeline, other_stage = create_crm_pipeline(account: other, user: create(:user, :administrator, account: other))

      post "#{base_url}/crm_cards", params: { lead_ids: [lead.id], pipeline_id: pipeline.id, stage_id: other_stage.id },
                                    headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:not_found)
      expect(account.crm_cards.count).to eq(0)
    end

    it 'agente sem permissão da prospecção não envia' do
      agent = create(:user, account: account, role: :agent)

      send_to_crm([create_lead(1).id], user: agent)

      expect(response).to have_http_status(:unauthorized)
      expect(account.crm_cards.count).to eq(0)
    end
  end

  describe 'POST leads/:id/crm_card (individual)' do
    it 'usa o mesmo caminho e devolve o mesmo resultado por lead' do
      lead = create_lead(1)

      post "#{base_url}/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
                                              headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:created)
      payload = response.parsed_body['payload']
      card_id = lead.reload.crm_card_id
      expect(payload['created']).to eq([{ 'lead_id' => lead.id, 'card_id' => card_id, 'contact_id' => lead.contact_id,
                                          'company_id' => account.companies.last.id }])
      expect(payload['existing']).to eq([])
      expect(payload['failed']).to eq([])
      expect(payload.dig('crm_card', 'id')).to eq(card_id)
      expect(payload.dig('lead', 'crm_status')).to eq('created')
    end

    it 'falha do lead vira 422 com o motivo, sem dizer que criou' do
      lead = create_lead(1)
      allow(Crm::Cards::Creator).to receive(:new).and_raise(ActiveRecord::RecordInvalid, Crm::Card.new)

      post "#{base_url}/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
                                              headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      body = response.parsed_body
      expect(body['code']).to eq('invalid_data')
      expect(body.dig('payload', 'created')).to eq([])
      expect(body.dig('payload', 'failed', 0, 'lead_id')).to eq(lead.id)
      expect(account.crm_cards.count).to eq(0)
    end
  end

  describe 'POST leads/campaign_segment' do
    def verified(lead)
      lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => lead.phone } })
      lead
    end

    it 'cria a lista da seleção, etiqueta quem pode e diz o motivo de quem ficou fora' do
      ready = verified(create_lead(1))
      no_whatsapp = create_lead(2)
      discarded = verified(create_lead(3, status: :discarded, discard_reason: 'Fora do perfil'))
      foreign = create_lead(4, target_account: create(:account))

      post "#{base_url}/campaign_segment",
           params: { lead_ids: [ready.id, no_whatsapp.id, discarded.id, foreign.id], segment_name: 'Restaurantes BH' },
           headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:created)
      segment = response.parsed_body.dig('payload', 'segment')
      expect(segment.values_at('eligible_count', 'blocked_count')).to eq([1, 3])
      reasons = segment['blocked_leads'].to_h { |row| [row['id'], row['reason_code']] }
      expect(reasons).to eq(no_whatsapp.id => 'no_whatsapp', discarded.id => 'discarded', foreign.id => 'not_found')
      expect(segment['blocked_leads'].find { |row| row['id'] == foreign.id }['name']).to be_nil
      expect(ready.reload.contact.label_list).to include(segment.dig('label', 'title'))
      expect(discarded.reload).to be_discarded

      list = response.parsed_body.dig('payload', 'list')
      expect([list['name'], list['lead_ids'].sort]).to eq(['Restaurantes BH', [ready.id, no_whatsapp.id, discarded.id].sort])
    end

    it 'reusa a lista de mesmo nome num segundo envio' do
      first = verified(create_lead(1))
      second = verified(create_lead(2))
      post "#{base_url}/campaign_segment", params: { lead_ids: [first.id], segment_name: 'Seleção' },
                                           headers: auth_headers(admin), as: :json

      post "#{base_url}/campaign_segment", params: { lead_ids: [second.id], segment_name: 'Seleção' },
                                           headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:created)
      expect(account.autonomia_prospecting_lists.where(name: 'Seleção').count).to eq(1)
      expect(response.parsed_body.dig('payload', 'segment', 'eligible_count')).to eq(2)
    end

    it 'sem ninguém elegível responde 422 com os motivos e não deixa lista para trás' do
      lead = create_lead(1)

      post "#{base_url}/campaign_segment", params: { lead_ids: [lead.id], segment_name: 'Nada' },
                                           headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq('prospecting.campaign.no_eligible_leads')
      expect(response.parsed_body.dig('payload', 'segment', 'blocked_leads', 0, 'reason_code')).to eq('no_whatsapp')
      expect(account.autonomia_prospecting_lists.count).to eq(0)
      expect(lead.reload).to be_new_lead
    end
  end
end

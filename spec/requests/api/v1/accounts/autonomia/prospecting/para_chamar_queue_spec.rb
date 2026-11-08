require 'rails_helper'

# A fila "Para chamar" (#2697, F5): GET leads?view=queue e o "Depois" (leads/:id/queue_postponement). Quem entra é a
# opção A, decidida pelo Rodrigo em 08/11: lead visível, new_lead, sem recusa, sem card, não fechado, com telefone e
# fora do "Depois" de quem pede.
RSpec.describe 'Autonomia prospecting para chamar queue', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:agent) { agent_with(%w[prospecting_manage]) }
  let(:other_agent) { agent_with(%w[prospecting_manage]) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def agent_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def create_lead(slug, owner: agent, target_account: account, **attributes)
    lead = Autonomia::Prospecting::Lead.create!(
      { account: target_account, provider: 'mock', provider_place_id: "places/#{slug}", name: "Lead #{slug}", phone: '+5519999990000',
        priority_score: 50 }.merge(attributes)
    )
    search = Autonomia::Prospecting::Search.create!(account: target_account, user: owner, query: slug, provider: 'mock', status: 'completed',
                                                    metadata: { 'lead_ids' => [lead.id] })
    lead.update!(search: search)
    lead
  end

  def queue_ids(user)
    get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(user)
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].pluck('id')
  end

  describe 'gate' do
    it 'conta sem a Prospecção ligada não abre a fila (404)' do
      Autonomia::Prospecting::Config.disable_for!(account)

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)

      expect(response).to have_http_status(:not_found)
    end

    it 'agente sem função de prospecção não vê a fila nem marca Depois' do
      plain = create(:user, account: account, role: :agent)
      lead = create_lead('sem-funcao')

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(plain)
      expect(response).to have_http_status(:unauthorized)

      post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(plain)
      expect(response).to have_http_status(:unauthorized)
    end

    it 'quem só vê a prospecção lê a fila, mas não marca Depois' do
      viewer = agent_with(%w[prospecting_view prospecting_view_all_searches])
      lead = create_lead('so-ver')

      expect(queue_ids(viewer)).to eq([lead.id])

      post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(viewer)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe 'quem entra' do
    it 'só as ainda não tratadas: fora descartada, recusada, no funil, fechada e sem telefone' do
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      card = account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: admin, title: 'Card')
      profile = Autonomia::Prospecting::CompanyProfile.create!(cnpj: '11222333000181', registration_status: 'BAIXADA', verified_at: Time.current)
      entra = create_lead('entra')
      create_lead('descartada', status: :discarded, discard_reason: 'nao_serve')
      create_lead('recusou', consent_refused_at: Time.current)
      create_lead('no-funil', crm_card: card)
      create_lead('fechada', company_research_status: 'confirmed', company_profile: profile)
      create_lead('sem-telefone', phone: nil)
      create_lead('telefone-vazio', phone: '')

      expect(queue_ids(admin)).to eq([entra.id])
    end

    it 'a situação do retrato da pesquisa vale antes do perfil, como na tela' do
      profile = Autonomia::Prospecting::CompanyProfile.create!(cnpj: '11222333000181', registration_status: 'BAIXADA', verified_at: Time.current)
      ativa = create_lead('retrato-ativa', company_research_status: 'confirmed', company_profile: profile,
                                           metadata: { 'research' => { 'company' => { 'registration_status' => 'ATIVA' } } })

      expect(queue_ids(admin)).to eq([ativa.id])
    end

    it 'a ordem é a da chance: prioridade maior primeiro, sem prioridade no fim' do
      media = create_lead('media', priority_score: 30)
      sem = create_lead('sem-prioridade', priority_score: nil)
      boa = create_lead('boa', priority_score: 90)

      expect(queue_ids(admin)).to eq([boa.id, media.id, sem.id])
    end

    it 'cada cartão leva quem achou a empresa (found_by_name)' do
      create_lead('achada', owner: other_agent)

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].first['found_by_name']).to eq(other_agent.name)
    end
  end

  describe 'visibilidade e IDOR' do
    let!(:own_lead) { create_lead('proprio', owner: agent) }
    let!(:other_lead) { create_lead('do-outro', owner: other_agent) }
    let(:other_account) { create(:account) }
    let!(:foreign_lead) { create_lead('outra-conta', owner: create(:user, account: other_account), target_account: other_account) }

    it 'o agente vê só os leads das próprias buscas; o administrador vê os da conta, nunca os de outra conta' do
      expect(queue_ids(agent)).to eq([own_lead.id])
      expect(queue_ids(admin)).to contain_exactly(own_lead.id, other_lead.id)
      expect(queue_ids(admin)).not_to include(foreign_lead.id)
    end

    it 'Depois em lead fora da visibilidade ou de outra conta é 404 e não grava nada' do
      [other_lead, foreign_lead].each do |lead|
        post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)
        expect(response).to have_http_status(:not_found)

        delete "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)
        expect(response).to have_http_status(:not_found)
        expect(lead.reload.metadata).not_to have_key('para_chamar')
      end
    end
  end

  describe 'Depois' do
    let!(:lead) { create_lead('depois', owner: agent, metadata: { 'whatsapp_verification' => { 'status' => 'verified' } }) }

    it 'some da fila de quem pediu até amanhã, sem sumir para os outros, e o resto do metadata fica' do
      travel_to Time.zone.parse('2026-11-08 10:00:00 -03:00') do
        post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('payload', 'postponed_on')).to eq('2026-11-08')
        expect(lead.reload.metadata).to include('whatsapp_verification' => { 'status' => 'verified' },
                                                'para_chamar' => { 'depois' => { agent.id.to_s => '2026-11-08' } })
        expect(queue_ids(agent)).to be_empty
        expect(queue_ids(admin)).to eq([lead.id])
      end

      travel_to Time.zone.parse('2026-11-09 08:00:00 -03:00') do
        expect(queue_ids(agent)).to eq([lead.id])
      end
    end

    it 'o Depois de duas pessoas convive no mesmo lead' do
      manager = agent_with(%w[prospecting_manage prospecting_view_all_searches])
      post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)
      post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(manager)

      expect(lead.reload.metadata.dig('para_chamar', 'depois').keys).to contain_exactly(agent.id.to_s, manager.id.to_s)
    end

    it 'o Desfazer devolve a empresa à fila, tirando só a marca de quem pediu' do
      post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)
      delete "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)

      expect(response).to have_http_status(:ok)
      expect(lead.reload.metadata.dig('para_chamar', 'depois')).to eq({})
      expect(lead.metadata['whatsapp_verification']).to eq('status' => 'verified')
      expect(queue_ids(agent)).to eq([lead.id])
    end
  end

  describe 'ações do cartão pelos endpoints de sempre' do
    let!(:lead) { create_lead('acao', owner: agent) }

    it '"Não serve" (descarte com motivo) tira da fila; o Desfazer (status new_lead) devolve' do
      post "#{base_path}/leads/discard", params: { lead_ids: [lead.id], reason: 'no_interest' }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(queue_ids(agent)).to be_empty

      patch "#{base_path}/leads/#{lead.id}", params: { lead: { status: 'new_lead' } }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(queue_ids(agent)).to eq([lead.id])
    end

    it 'mandado ao funil sai da fila, e o lead diz a etapa e o dono que o bloco de sucesso mostra' do
      pipeline, stage = create_crm_pipeline(account: account, user: admin)

      post "#{base_path}/leads/crm_cards", params: { lead_ids: [lead.id], pipeline_id: pipeline.id, stage_id: stage.id },
                                           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'created').pluck('lead_id')).to eq([lead.id])
      expect(queue_ids(admin)).to be_empty

      get "#{base_path}/leads/#{lead.id}", headers: auth_headers(admin)
      expect(response.parsed_body.dig('payload', 'crm_presence')).to include('stage_name' => stage.name, 'owner_name' => admin.name)
    end
  end
end

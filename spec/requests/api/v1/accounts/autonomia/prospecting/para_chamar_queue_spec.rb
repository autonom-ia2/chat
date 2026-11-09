require 'rails_helper'

# A fila "Para chamar" (#2697, F5): GET leads?view=queue e o "Depois" (leads/:id/queue_postponement). Quem entra é a
# opção A, decidida pelo Rodrigo em 08/11: lead visível, new_lead, sem recusa, sem card, não fechado, com telefone e
# fora do "Depois" de quem pede.
RSpec.describe 'Autonomia prospecting para chamar queue', type: :request do
  # Fuso da conta explícito (−03): o "dia" do "Depois" é o da conta, não o do servidor.
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
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

    it 'quem vê as buscas de todos recebe quem achou a empresa (found_by_name)' do
      create_lead('achada', owner: other_agent)

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)

      expect(response.parsed_body['payload'].first['found_by_name']).to eq(other_agent.name)
    end

    it 'quem vê só as próprias buscas não recebe o nome de ninguém' do
      create_lead('minha', owner: agent)

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(agent)

      expect(response.parsed_body['payload'].size).to eq(1)
      expect(response.parsed_body['payload'].first).not_to have_key('found_by_name')
    end

    it 'mostra até o teto, diz quando passou dele (meta.truncated) e qual é (meta.max)' do
      stub_const('Autonomia::Prospecting::ParaChamar::MAX_LEADS', 2)
      create_lead('um', priority_score: 90)
      create_lead('dois', priority_score: 80)

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)
      expect(response.parsed_body['payload'].size).to eq(2)
      expect(response.parsed_body.dig('meta', 'truncated')).to be(false)

      create_lead('tres', priority_score: 70)
      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)
      expect(response.parsed_body['payload'].pluck('name')).to eq(['Lead um', 'Lead dois'])
      expect(response.parsed_body['meta']).to eq('truncated' => true, 'max' => 2)
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

    # 22:30 de 08/11 na conta (−03) já é 09/11 em UTC: o dia gravado e o "volta amanhã" são os da conta.
    it 'some da fila de quem pediu até o dia seguinte da conta, sem sumir para os outros, e o resto do metadata fica' do
      travel_to Time.zone.parse('2026-11-08 22:30:00 -03:00') do
        expect(Time.now.utc.to_date.iso8601).to eq('2026-11-09')
        post "#{base_path}/leads/#{lead.id}/queue_postponement", headers: auth_headers(agent)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body.dig('payload', 'postponed_on')).to eq('2026-11-08')
        expect(lead.reload.metadata).to include('whatsapp_verification' => { 'status' => 'verified' },
                                                'para_chamar' => { 'depois' => { agent.id.to_s => '2026-11-08' } })
        # Some para quem pediu (agent) e continua para os outros (admin).
        expect([queue_ids(agent), queue_ids(admin)]).to eq([[], [lead.id]])
      end

      travel_to Time.zone.parse('2026-11-08 23:59:00 -03:00') do
        expect(queue_ids(agent)).to be_empty
      end

      travel_to Time.zone.parse('2026-11-09 00:01:00 -03:00') do
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

  # Contrato com a tela (cartaoDaFila, acharLead.js): o JSON de verdade do render_queue fica em spec/fixtures, e o vitest
  # (ParaChamarPage.api.spec.js) monta o cartão a partir dele. Este spec falha quando as chaves do payload mudam ou o
  # arquivo falta, e nunca o escreve sozinho. Para regravar, rode com REGRAVAR_FIXTURE=1 e releia o arquivo antes de
  # commitar (o repo é público: só nomes de exemplo).
  describe 'contrato com a tela' do
    let(:fixture) { Rails.root.join('spec/fixtures/prospecting_para_chamar_queue.json') }

    def deep_keys(value)
      case value
      when Hash then value.transform_values { |item| deep_keys(item) }.sort.to_h
      when Array then value.first(1).map { |item| deep_keys(item) }
      else value&.class&.name
      end
    end

    it 'o payload real tem as mesmas chaves do arquivo que o vitest lê' do
      profile = Autonomia::Prospecting::CompanyProfile.create!(cnpj: '11222333000181', trade_name: 'Padaria Exemplo', registration_status: 'ATIVA',
                                                               verified_at: Time.zone.parse('2026-11-01 10:00'))
      create_lead('contrato', owner: other_agent, category: 'Padaria', neighborhood: 'Centro', human_insight: 'Nota boa no Google.',
                              rating: 4.6, reviews_count: 120, company_profile: profile, company_research_status: 'confirmed',
                              decision_research_status: 'confirmed', decision_name: 'Maria Exemplo', decision_role: 'sócia',
                              metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5519999990000' } })

      get "#{base_path}/leads", params: { view: 'queue' }, headers: auth_headers(admin)
      body = response.parsed_body
      fixture.write("#{JSON.pretty_generate(body)}\n") if ENV['REGRAVAR_FIXTURE'] == '1'

      expect(fixture).to exist, "Falta #{fixture}. Regrave com: REGRAVAR_FIXTURE=1 bundle exec rspec #{__FILE__}"
      expect(deep_keys(body)).to eq(deep_keys(JSON.parse(fixture.read)))
    end
  end

  describe 'ações do cartão pelos endpoints de sempre' do
    let!(:lead) { create_lead('acao', owner: agent) }

    it '"Não serve" (descarte com motivo) tira da fila; o Desfazer (status new_lead) devolve' do
      post "#{base_path}/leads/discard", params: { lead_ids: [lead.id], reason: 'no_interest' }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(queue_ids(agent)).to be_empty

      expect(lead.reload.discard_reason).to eq('no_interest')

      # O "Desfazer": o PATCH de status de sempre já limpa o motivo quando o status não é discarded (lead_params).
      patch "#{base_path}/leads/#{lead.id}", params: { lead: { status: 'new_lead' } }, headers: auth_headers(agent)
      expect(response).to have_http_status(:ok)
      expect(lead.reload).to have_attributes(status: 'new_lead', discard_reason: nil)
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

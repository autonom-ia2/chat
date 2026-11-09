require 'rails_helper'

# "Suas listas" da Prospecção nova (#2775, F6): os Públicos criados pela Prospecção, com números, pôr, tirar, devolver,
# copiar e em quais listas a empresa está. Pede prospecting_manage e campaign_manage; só listas da conta e da Prospecção.
RSpec.describe 'Autonomia prospecting audiences', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:audiences_on) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "req-lists-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-41#{index.to_s.rjust(2, '0')}", country: 'BR', **attributes
    )
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def call(verb, path, user: admin, params: {})
    with_modified_env(audiences_on) { public_send(verb, "#{base}#{path}", params: params, headers: auth_headers(user), as: :json) }
  end

  def save_list(leads, name: 'Padarias')
    call(:post, '/leads/audience', params: { lead_ids: leads.map(&:id), name: name })
    account.campaign_imports.find(response.parsed_body.dig('payload', 'audience', 'id'))
  end

  def lock!(audience)
    campaign = create(:campaign, account: account)
    campaign.update_columns(campaign_status: Campaign.campaign_statuses['completed']) # rubocop:disable Rails/SkipsModelValidations
    CampaignAudienceLink.create!(account: account, campaign: campaign, campaign_import: audience)
  end

  def other_origin_list(contact)
    CampaignJourney::AudienceWriter.new(account, user: admin, source: 'conversations')
                                   .perform('Outra origem', [CampaignJourney::AudienceWriter::Row.new(contact_id: contact.id, name: 'x')])
  end

  def payload
    response.parsed_body['payload']
  end

  describe 'GET audiences' do
    it 'lista só as da Prospecção desta conta, com os números (sem número de "já chamadas")' do
      first = create_lead(1, enriched_email: 'a@empresa1.com.br')
      list = save_list([first, create_lead(2)])
      pipeline, stage = create_crm_pipeline(account: account, user: admin)
      Crm::Card.create!(account: account, pipeline: pipeline, stage: stage, title: 'Card', currency: 'BRL', contact: first.reload.contact)
      other_origin_list(first.contact)

      call(:get, '/audiences')

      expect(response).to have_http_status(:ok)
      expect(payload.map { |item| item['id'] }).to eq([list.id])
      expect(payload.first).to include('name' => 'Padarias', 'companies' => 2, 'whatsapp' => 2, 'email' => 1,
                                       'in_crm' => 1, 'locked' => false)
      expect(payload.first).not_to have_key('called')
      expect(response.parsed_body['meta']).to include('total_count' => 1, 'has_more' => false)
    end

    it 'pagina por cursor: has_more enquanto há mais listas, e o cursor traz o resto' do
      stub_const('Api::V1::Accounts::Autonomia::Prospecting::AudiencesController::DEFAULT_PER_PAGE', 1)
      older = save_list([create_lead(1)], name: 'Antiga')
      newer = save_list([create_lead(2)], name: 'Nova')

      call(:get, '/audiences')
      expect(payload.map { |item| item['id'] }).to eq([newer.id])
      meta = response.parsed_body['meta']
      expect(meta).to include('has_more' => true, 'total_count' => 2, 'next_before_id' => newer.id)

      call(:get, '/audiences', params: { before_at: meta['next_before_at'], before_id: meta['next_before_id'] })
      expect(payload.map { |item| item['id'] }).to eq([older.id])
      expect(response.parsed_body['meta']).to include('has_more' => false, 'next_before_id' => nil)
    end

    # Revisão do #2775, rodada 2, item 3: com offset, apagar uma lista já mostrada fazia a página seguinte pular uma.
    it 'uma lista apagada entre um "Ver mais" e outro não faz pular nenhuma' do
      stub_const('Api::V1::Accounts::Autonomia::Prospecting::AudiencesController::DEFAULT_PER_PAGE', 2)
      oldest, middle, newer, newest = (1..4).map { |index| save_list([create_lead(index)], name: "L#{index}") }

      call(:get, '/audiences')
      expect(payload.map { |item| item['id'] }).to eq([newest.id, newer.id])
      meta = response.parsed_body['meta']
      newest.destroy!

      call(:get, '/audiences', params: { before_at: meta['next_before_at'], before_id: meta['next_before_id'] })
      expect(payload.map { |item| item['id'] }).to eq([middle.id, oldest.id])
    end

    it 'cursor inválido: 422 invalid_cursor' do
      call(:get, '/audiences', params: { before_at: 'ontem', before_id: 1 })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.invalid_cursor')
    end

    it 'com lead_ids, diz quais desses leads já estão em cada lista' do
      inside = create_lead(1)
      list = save_list([inside])
      outside = create_lead(2)

      call(:get, '/audiences', params: { lead_ids: [inside.id, outside.id] })

      expect(payload.first).to include('id' => list.id, 'already_lead_ids' => [inside.id])
    end

    # Revisão do #2775, rodada 2, item 4: already_lead_ids só fala de leads que quem pede vê.
    it 'lead de outra conta ou que a pessoa não vê não aparece em already_lead_ids' do
      foreign_account = create(:account)
      foreign_lead = Autonomia::Prospecting::Lead.create!(account: foreign_account, provider: 'mock', provider_place_id: 'req-lists-leak',
                                                          name: 'Fora', country: 'BR')
      hidden = create_lead(1)
      list = save_list([hidden])
      # O pior caso: um lead de outra conta apontando para o mesmo contato (a validação do modelo impede; a consulta também).
      foreign_lead.update_columns(contact_id: hidden.reload.contact_id) # rubocop:disable Rails/SkipsModelValidations
      agent = agent_with(%w[prospecting_view prospecting_manage campaign_manage])

      call(:get, '/audiences', params: { lead_ids: [foreign_lead.id] })
      expect(payload.first).to include('id' => list.id, 'already_lead_ids' => [])

      call(:get, '/audiences', user: agent, params: { lead_ids: [hidden.id] })
      expect(payload.first).to include('id' => list.id, 'already_lead_ids' => [])
    end

    it 'com mais lead_ids que o teto: 422 too_many_members' do
      call(:get, '/audiences', params: { lead_ids: (1..101).to_a })

      expect(response.parsed_body['code']).to eq('prospecting.audience.too_many_members')
    end

    it 'marca a lista já enviada' do
      list = save_list([create_lead(1)])
      lock!(list)

      call(:get, '/audiences')

      expect(payload.first).to include('id' => list.id, 'locked' => true)
    end

    it 'sem campaign_manage: 403' do
      call(:get, '/audiences', user: agent_with(%w[prospecting_view prospecting_manage]))

      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body['code']).to eq('prospecting.campaign.forbidden')
    end

    it 'sem os Públicos ligados: 404' do
      get "#{base}/audiences", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'GET audiences/:id' do
    it 'abre a lista com as empresas, paginadas, e o lead que a pessoa vê' do
      leads = [create_lead(1), create_lead(2)]
      list = save_list(leads)

      call(:get, "/audiences/#{list.id}")

      expect(payload['members'].map { |member| [member['row_number'], member['lead_id'], member['whatsapp']] })
        .to eq([[1, leads[0].id, true], [2, leads[1].id, true]])
      expect(payload['members'].first).not_to have_key('called')
      expect(response.parsed_body['meta']).to include('total_count' => 2, 'next_after' => nil, 'has_more' => false)
    end

    # Revisão do #2775, item 2: com offset, tirar alguém da 1ª página fazia a 2ª pular uma empresa.
    it 'pagina pelo cursor: tirar alguém da página aberta não faz a próxima pular ninguém' do
      stub_const('Autonomia::Prospecting::AudienceLists::MEMBERS_PER_PAGE', 2)
      leads = [create_lead(1), create_lead(2), create_lead(3)]
      list = save_list(leads)

      call(:get, "/audiences/#{list.id}")
      expect(payload['members'].pluck('row_number')).to eq([1, 2])
      expect(response.parsed_body['meta']).to include('next_after' => 2, 'has_more' => true)

      call(:delete, "/audiences/#{list.id}/members", params: { lead_ids: [leads[0].id] })
      call(:get, "/audiences/#{list.id}", params: { after: 2 })

      expect(payload['members'].map { |member| [member['row_number'], member['lead_id']] }).to eq([[3, leads[2].id]])
      expect(response.parsed_body['meta']).to include('next_after' => nil, 'has_more' => false, 'total_count' => 2)
    end

    it 'lista de outra conta ou de outra origem: 404' do
      other_origin = other_origin_list(create(:contact, account: account))
      foreign_account = create(:account)
      foreign = CampaignJourney::AudienceWriter.new(foreign_account, user: admin, source: 'prospecting')
                                               .perform('De fora', [CampaignJourney::AudienceWriter::Row.new(
                                                 contact_id: create(:contact, account: foreign_account).id, name: 'x'
                                               )])

      call(:get, "/audiences/#{other_origin.id}")
      expect(response).to have_http_status(:not_found)

      call(:get, "/audiences/#{foreign.id}")
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'POST audiences/:id/leads' do
    it 'acrescenta no fim; quem já está sai como already_in_list' do
      first = create_lead(1)
      list = save_list([first])
      second = create_lead(2)

      call(:post, "/audiences/#{list.id}/leads", params: { lead_ids: [first.id, second.id] })

      expect(response).to have_http_status(:ok)
      expect(payload['entered_lead_ids']).to eq([second.id])
      expect(payload['left_out'].map { |item| [item['lead_id'], item['reason_code']] }).to eq([[first.id, 'already_in_list']])
      expect(payload.dig('audience', 'companies')).to eq(2)
      expect(list.campaign_import_rows.order(:row_number).map { |row| [row.contact_id, row.row_number] })
        .to eq([[first.reload.contact_id, 1], [second.reload.contact_id, 2]])
      expect(list.reload.valid_rows).to eq(2)
    end

    it 'todas já estavam na lista: 422 all_already_in_list, com a frase certa' do
      first = create_lead(1)
      list = save_list([first])

      call(:post, "/audiences/#{list.id}/leads", params: { lead_ids: [first.id] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.all_already_in_list')
      expect(response.parsed_body['error']).to start_with(I18n.t('autonomia.prospecting.audience.errors.all_already_in_list'))
      expect(response.parsed_body['left_out'].map { |item| item['reason_code'] }).to eq(['already_in_list'])
    end

    it 'o mesmo teto do Guardar lista' do
      list = save_list([create_lead(1)])

      call(:post, "/audiences/#{list.id}/leads", params: { lead_ids: (1..101).to_a })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.too_many_leads')
    end

    it 'lista já enviada: 422 audience_locked, sem criar contato' do
      list = save_list([create_lead(1)])
      lock!(list)
      fresh = create_lead(2)

      call(:post, "/audiences/#{list.id}/leads", params: { lead_ids: [fresh.id] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.audience_locked')
      expect(fresh.reload.contact_id).to be_nil
    end
  end

  describe 'DELETE e POST audiences/:id/members' do
    it 'tira pelo lead, devolve pelo contato, na mesma linha' do
      leads = [create_lead(1), create_lead(2)]
      list = save_list(leads)
      contact_id = leads[0].reload.contact_id

      call(:delete, "/audiences/#{list.id}/members", params: { lead_ids: [leads[0].id] })

      expect(response).to have_http_status(:ok)
      expect(payload['removed_contact_ids']).to eq([contact_id])
      expect(payload.dig('audience', 'companies')).to eq(1)
      expect(list.campaign_import_rows.find_by(contact_id: contact_id).status).to eq('removed')

      call(:post, "/audiences/#{list.id}/members", params: { contact_ids: [contact_id] })

      expect(payload['restored_contact_ids']).to eq([contact_id])
      expect(list.campaign_import_rows.where(contact_id: contact_id).pluck(:row_number, :status)).to eq([[1, 'imported']])
      expect(list.reload.valid_rows).to eq(2)
    end

    it 'devolver não põe quem nunca esteve na lista' do
      list = save_list([create_lead(1)])
      stranger = create(:contact, account: account, phone_number: '+5531988887777')

      call(:post, "/audiences/#{list.id}/members", params: { contact_ids: [stranger.id] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(list.campaign_import_rows.where(contact_id: stranger.id)).to be_empty
    end

    it 'tirar de lista já enviada: 422' do
      lead = create_lead(1)
      list = save_list([lead])
      lock!(list)

      call(:delete, "/audiences/#{list.id}/members", params: { contact_ids: [lead.reload.contact_id] })

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.audience_locked')
    end

    it 'lead_ids de outra conta não tiram ninguém: 422 no_members' do
      lead = create_lead(1)
      list = save_list([lead])
      foreign_account = create(:account)
      foreign_lead = Autonomia::Prospecting::Lead.create!(account: foreign_account, provider: 'mock', provider_place_id: 'req-lists-fora',
                                                          name: 'Fora', country: 'BR',
                                                          contact: create(:contact, account: foreign_account))

      call(:delete, "/audiences/#{list.id}/members", params: { lead_ids: [foreign_lead.id] })

      expect(response.parsed_body['code']).to eq('prospecting.audience.no_members')
      expect(list.campaign_import_rows.pluck(:status)).to eq(['imported'])
    end

    it 'mais ids que o teto: 422 too_many_members, sem cortar em silêncio' do
      list = save_list([create_lead(1)])
      ids = (1..101).to_a

      call(:delete, "/audiences/#{list.id}/members", params: { contact_ids: ids })
      expect(response.parsed_body['code']).to eq('prospecting.audience.too_many_members')

      call(:delete, "/audiences/#{list.id}/members", params: { lead_ids: ids })
      expect(response.parsed_body['code']).to eq('prospecting.audience.too_many_members')

      call(:post, "/audiences/#{list.id}/members", params: { contact_ids: ids })
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.too_many_members')
      expect(list.campaign_import_rows.pluck(:status)).to eq(['imported'])
    end

    it 'sem ninguém para tirar: 422 no_members' do
      list = save_list([create_lead(1)])

      call(:delete, "/audiences/#{list.id}/members", params: { contact_ids: ['abc'] })

      expect(response.parsed_body['code']).to eq('prospecting.audience.no_members')
    end
  end

  describe 'POST audiences/:id/copy' do
    it 'cria uma lista nova da Prospecção com quem está hoje, com o nome no idioma da conta' do
      account.update!(locale: 'pt_BR')
      leads = [create_lead(1), create_lead(2)]
      list = save_list(leads)
      lock!(list)

      call(:post, "/audiences/#{list.id}/copy")

      expect(response).to have_http_status(:created)
      copy = account.campaign_imports.find(payload['id'])
      expect(copy.name).to eq('Padarias (cópia)')
      expect(copy.options['source']).to eq('prospecting')
      expect(payload).to include('companies' => 2, 'locked' => false)
    end

    # Revisão do #2775, item 10: o writer liga todo canal com gente; a cópia segue o ligado/desligado da original.
    it 'a cópia herda o canal desligado da original' do
      list = save_list([create_lead(1, enriched_email: 'a@empresa1.com.br')])
      list.update!(channels: list.channels.merge('whatsapp' => list.channels['whatsapp'].merge('enabled' => false)))

      call(:post, "/audiences/#{list.id}/copy")

      copy = account.campaign_imports.find(payload['id'])
      expect(copy.channels['whatsapp']).to include('enabled' => false, 'count' => 1)
      expect(copy.channels['email']).to include('enabled' => true, 'count' => 1)
    end
  end

  describe 'escrita sem campaign_manage' do
    let(:agent) { agent_with(%w[prospecting_view prospecting_manage]) }

    it '403 em pôr, tirar, devolver e copiar, sem mudar a lista' do
      lead = create_lead(1)
      list = save_list([lead])
      contact_id = lead.reload.contact_id

      [
        [:post, "/audiences/#{list.id}/leads", { lead_ids: [lead.id] }],
        [:delete, "/audiences/#{list.id}/members", { contact_ids: [contact_id] }],
        [:post, "/audiences/#{list.id}/members", { contact_ids: [contact_id] }],
        [:post, "/audiences/#{list.id}/copy", {}]
      ].each do |verb, path, params|
        call(verb, path, user: agent, params: params)
        expect(response).to have_http_status(:forbidden), "#{verb} #{path}"
        expect(response.parsed_body['code']).to eq('prospecting.campaign.forbidden')
      end
      expect(list.campaign_import_rows.pluck(:status)).to eq(['imported'])
      expect(account.campaign_imports.count).to eq(1)
    end
  end

  describe 'GET leads/:id/audiences' do
    it 'em quais listas a empresa está' do
      lead = create_lead(1)
      list = save_list([lead])
      save_list([create_lead(2)], name: 'Outra')

      call(:get, "/leads/#{lead.id}/audiences")

      expect(payload).to eq([{ 'id' => list.id, 'name' => 'Padarias', 'locked' => false }])
    end

    it 'lead que a pessoa não vê: 404' do
      lead = create_lead(1)

      call(:get, "/leads/#{lead.id}/audiences", user: agent_with(%w[prospecting_view prospecting_manage campaign_manage]))

      expect(response).to have_http_status(:not_found)
    end
  end
end

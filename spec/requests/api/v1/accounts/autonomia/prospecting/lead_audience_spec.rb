require 'rails_helper'

# "Guardar para mandar mensagem" da Prospecção nova (#2695, F3b): os leads escolhidos viram um Público de Campanhas
# (source 'prospecting'), com contato e empresa pela regra do ContactConverter. Quem pediu para parar ou não tem
# telefone nem e-mail fica de fora, com o motivo. Pede prospecting_manage e campaign_manage.
RSpec.describe 'Autonomia prospecting lead audience', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting/leads/audience" }
  let(:audiences_on) { { 'CAMPAIGN_JOURNEY_ENABLED' => 'true', 'CAMPAIGN_IMPORT_ENABLED' => 'true' } }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "req-audience-#{index}", name: "Empresa #{index}",
      phone: "+55 31 99999-40#{index.to_s.rjust(2, '0')}", country: 'BR', **attributes
    )
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  def save_audience(lead_ids, user: admin, name: 'Padarias · Centro')
    with_modified_env(audiences_on) do
      post path, params: { lead_ids: lead_ids, name: name }, headers: auth_headers(user), as: :json
    end
  end

  def left_out_reasons
    response.parsed_body.dig('payload', 'left_out').to_h { |item| [item['lead_id'], item['reason_code']] }
  end

  it 'cria o Público com source prospecting e devolve quantos entraram' do
    leads = [create_lead(1), create_lead(2)]

    save_audience(leads.map(&:id))

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    audience = account.campaign_imports.find(payload.dig('audience', 'id'))
    expect(audience).to have_attributes(name: 'Padarias · Centro', status: 'completed', valid_rows: 2)
    expect(audience.options['source']).to eq('prospecting')
    expect(payload).to include('entered_lead_ids' => leads.map(&:id), 'left_out' => [])
    expect(payload['audience']).to include('count' => 2)
  end

  it 'o contato sai pela regra: com decisor é a pessoa, sem decisor é a empresa; os dois ligados à empresa' do
    owner = create_lead(1, decision_name: 'Ana Souza', decision_role: 'Sócia')
    company = create_lead(2, enriched_email: 'contato@empresa2.com.br')

    save_audience([owner.id, company.id])

    audience = account.campaign_imports.find(response.parsed_body.dig('payload', 'audience', 'id'))
    person = owner.reload.contact
    expect(person).to have_attributes(name: 'Ana Souza', phone_number: '+5531999994001')
    expect(person.company.name).to eq('Empresa 1')
    business = company.reload.contact
    expect(business).to have_attributes(name: 'Empresa 2', email: 'contato@empresa2.com.br')
    expect(business.company.name).to eq('Empresa 2')
    expect(audience.campaign_import_rows.order(:row_number).map(&:contact_id)).to eq([person.id, business.id])
    expect(audience.campaign_import_rows.order(:row_number).map(&:company_name)).to eq(['Empresa 1', 'Empresa 2'])
  end

  it 'deixa de fora, com o motivo, quem recusou, quem não tem canal e o descartado, sem criar contato para eles' do
    good = create_lead(1)
    refused = create_lead(2, status: :no_consent)
    silent = create_lead(3, phone: nil)
    discarded = create_lead(4, status: :discarded, discard_reason: 'Fechou')
    opted_contact = create(:contact, account: account, phone_number: '+5531999994005', opted_out_at: 1.day.ago)
    reaches_opted = create_lead(5)

    save_audience([good, refused, silent, discarded, reaches_opted].map(&:id))

    expect(response).to have_http_status(:created)
    expect(left_out_reasons).to eq(refused.id => 'opt_out', silent.id => 'no_channel', discarded.id => 'discarded',
                                   reaches_opted.id => 'opt_out')
    expect(response.parsed_body.dig('payload', 'left_out').first['message']).to eq(I18n.t('autonomia.prospecting.audience.left_out.opt_out'))
    expect(response.parsed_body.dig('payload', 'audience', 'count')).to eq(1)
    expect([refused, silent, discarded].map { |lead| lead.reload.contact_id }).to all(be_nil)
    expect(CampaignImportRow.where(contact_id: opted_contact.id)).to be_empty
  end

  it 'ninguém entra: 422 com a frase e quem ficou de fora' do
    silent = create_lead(1, phone: nil)

    expect { save_audience([silent.id]) }.not_to change(CampaignImport, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'prospecting.audience.no_rows',
                                            'error' => I18n.t('autonomia.prospecting.audience.errors.no_rows'))
    expect(response.parsed_body['left_out'].map { |item| item['reason_code'] }).to eq(['no_channel'])
  end

  it 'contato apagado no meio: o writer recusa e vira 422 com a frase, quem ficou de fora e o aviso dos contatos' do
    lead = create_lead(1)
    silent = create_lead(2, phone: nil)
    allow(CampaignJourney::AudienceWriter).to receive(:new).and_wrap_original do |original, *args, **kwargs|
      original.call(*args, **kwargs).tap do |writer|
        allow(writer).to receive(:perform).and_wrap_original do |perform, name, rows|
          Contact.where(id: rows.map(&:contact_id)).delete_all
          perform.call(name, rows)
        end
      end
    end

    expect { save_audience([lead.id, silent.id]) }.not_to change(CampaignImport, :count)

    expect(response).to have_http_status(:unprocessable_entity)
    expected = "#{I18n.t('autonomia.prospecting.audience.errors.foreign_contact')} " \
               "#{I18n.t('autonomia.prospecting.audience.errors.contacts_saved')}"
    expect(response.parsed_body).to include('code' => 'prospecting.audience.foreign_contact', 'error' => expected)
    expect(response.parsed_body['left_out'].map { |item| item['reason_code'] }).to eq(['no_channel'])
  end

  describe 'quem o pedido alcança' do
    it 'lead de outra conta fica de fora como não encontrado' do
      foreign = Autonomia::Prospecting::Lead.create!(account: create(:account), provider: 'mock', provider_place_id: 'req-audience-foreign',
                                                     name: 'De fora', phone: '+55 31 99999-4099', country: 'BR')

      save_audience([foreign.id])

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['left_out']).to eq([{ 'lead_id' => foreign.id, 'reason_code' => 'not_found',
                                                        'message' => I18n.t('autonomia.prospecting.audience.left_out.not_found') }])
      expect(foreign.reload.contact_id).to be_nil
    end

    it 'lead que o agente não vê (sem Ver buscas de todos) fica de fora como não encontrado' do
      hidden = create_lead(1)

      save_audience([hidden.id], user: agent_with(%w[prospecting_view prospecting_manage campaign_manage]))

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['left_out'].map { |item| item['reason_code'] }).to eq(['not_found'])
      expect(hidden.reload.contact_id).to be_nil
    end
  end

  it 'lead_ids vazio responde 422 no_leads' do
    save_audience([])

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'prospecting.audience.no_leads',
                                            'error' => I18n.t('autonomia.prospecting.audience.errors.no_leads'))
  end

  it 'lead_ids de tipo inválido (objeto, lista, booleano, texto que não é número) responde 422 no_leads, não 500' do
    [[{ 'id' => 1 }], [[1]], true, ['0x1A', 'abc', '-3']].each do |invalid|
      save_audience(invalid)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.audience.no_leads')
    end
  end

  it 'acima do teto responde 422 com o máximo na frase' do
    stub_const('Autonomia::Prospecting::AudienceFromLeads::MAX_LEADS', 2)
    leads = Array.new(3) { |index| create_lead(index) }

    save_audience(leads.map(&:id))

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body).to include('code' => 'prospecting.audience.too_many_leads',
                                            'error' => I18n.t('autonomia.prospecting.audience.errors.too_many_leads', max: 2))
    expect(leads.map { |lead| lead.reload.contact_id }).to all(be_nil)
  end

  it 'dois leads no mesmo contato: entra o primeiro, o outro sai com same_contact' do
    first = create_lead(1)
    same = create_lead(2, phone: first.phone)

    save_audience([first.id, same.id])

    expect(response).to have_http_status(:created)
    payload = response.parsed_body['payload']
    expect(payload['entered_lead_ids']).to eq([first.id])
    expect(left_out_reasons).to eq(same.id => 'same_contact')
    expect(payload['left_out'].first['message']).to eq(I18n.t('autonomia.prospecting.audience.left_out.same_contact'))
    expect(payload.dig('audience', 'count')).to eq(1)
  end

  it 'contato que já existia é reaproveitado, sem criar outro' do
    existing = create(:contact, account: account, name: 'Já cadastrado', phone_number: '+5531999994001')
    lead = create_lead(1)

    expect { save_audience([lead.id]) }.not_to change(Contact, :count)

    audience = account.campaign_imports.find(response.parsed_body.dig('payload', 'audience', 'id'))
    expect(audience.campaign_import_rows.pluck(:contact_id)).to eq([existing.id])
    expect(lead.reload.contact_id).to eq(existing.id)
  end

  it 'e-mail inválido sem telefone fica de fora como sem canal, sem gravar contato (mesma régua do conversor)' do
    lead = create_lead(1, phone: nil, enriched_email: 'nao-e-um-email')

    expect { save_audience([lead.id]) }.not_to change(Contact, :count)

    expect(response.parsed_body['left_out'].map { |item| item['reason_code'] }).to eq(['no_channel'])
    expect(lead.reload.contact_id).to be_nil
  end

  it 'falha inesperada de um lead vai para o tracker e vira unexpected_error, sem derrubar os outros' do
    broken = create_lead(1)
    good = create_lead(2)
    allow(Autonomia::Prospecting::ContactConverter).to receive(:new).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap do |converter|
        allow(converter).to receive(:perform).and_raise(RuntimeError, 'quebrou') if kwargs[:lead].id == broken.id
      end
    end
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    save_audience([broken.id, good.id])

    expect(response).to have_http_status(:created)
    expect(left_out_reasons).to eq(broken.id => 'unexpected_error')
    expect(response.parsed_body.dig('payload', 'entered_lead_ids')).to eq([good.id])
    expect(tracker).to have_received(:capture_exception)
  end

  it 'sem nome responde 422 antes de criar qualquer contato' do
    lead = create_lead(1)

    save_audience([lead.id], name: '  ')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['code']).to eq('prospecting.audience.name_required')
    expect(lead.reload.contact_id).to be_nil
  end

  it 'sem campaign_manage responde 403 e nada é gravado' do
    lead = create_lead(1)
    agent = agent_with(%w[prospecting_view prospecting_manage])

    expect { save_audience([lead.id], user: agent) }.not_to change(CampaignImport, :count)

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body['code']).to eq('prospecting.campaign.forbidden')
    expect(lead.reload.contact_id).to be_nil
  end

  it 'com campaign_manage e a prospecção, a função personalizada guarda' do
    lead = create_lead(1)

    save_audience([lead.id], user: agent_with(%w[prospecting_view prospecting_manage prospecting_view_all_searches campaign_manage]))

    expect(response).to have_http_status(:created)
  end

  it 'com os Públicos desligados responde 404 com a frase' do
    lead = create_lead(1)

    post path, params: { lead_ids: [lead.id], name: 'X' }, headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
    expect(response.parsed_body['code']).to eq('prospecting.audience.disabled')
  end
end

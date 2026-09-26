require 'rails_helper'

# Descartar e criar contatos em lote (#732, item 10). As duas ações pedem a prospecção (prospecting_manage), como as
# outras ações do lead; quem só vê a prospecção recebe 401 e nada muda.
RSpec.describe 'Autonomia prospecting discard and bulk contacts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_path) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index, target_account: account, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: target_account, provider: 'mock', provider_place_id: "req-discard-#{target_account.id}-#{index}",
      name: "Empresa #{index}", phone: "+55 31 99999-30#{index.to_s.rjust(2, '0')}", country: 'BR', **attributes
    )
  end

  def agent_with(permissions)
    agent = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    agent.account_users.find_by(account: account).update!(custom_role: role)
    agent
  end

  describe 'POST leads/discard' do
    it 'descarta a seleção com o motivo e devolve os leads como a tela lê' do
      leads = Array.new(2) { |index| create_lead(index) }

      post "#{base_path}/leads/discard", params: { lead_ids: leads.map(&:id), reason: 'Sem interesse' },
                                         headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['leads'].map { |lead| [lead['status'], lead['discard_reason']] }).to eq([['discarded', 'Sem interesse']] * 2)
      expect(payload['missing_lead_ids']).to eq([])
      expect(leads.map { |lead| lead.reload.status }).to eq(%w[discarded discarded])
    end

    it 'lead de outra conta não é descartado' do
      foreign = create_lead(1, target_account: create(:account))

      post "#{base_path}/leads/discard", params: { lead_ids: [foreign.id], reason: 'X' }, headers: auth_headers(admin), as: :json

      expect(response.parsed_body.dig('payload', 'missing_lead_ids')).to eq([foreign.id])
      expect(foreign.reload.status).to eq('new_lead')
    end

    it 'sem motivo responde 422 com a frase e o código' do
      lead = create_lead(1)

      post "#{base_path}/leads/discard", params: { lead_ids: [lead.id], reason: ' ' }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body).to include('code' => 'prospecting.discard.missing_reason',
                                              'error' => I18n.t('autonomia.prospecting.lead_discard.errors.missing_reason'))
      expect(lead.reload.status).to eq('new_lead')
    end

    it 'quem só vê a prospecção não descarta' do
      lead = create_lead(1)

      post "#{base_path}/leads/discard", params: { lead_ids: [lead.id], reason: 'X' },
                                         headers: auth_headers(agent_with(['prospecting_view'])), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(lead.reload.status).to eq('new_lead')
    end

    it 'desfazer o descarte pelo lead volta a novo e apaga o motivo' do
      lead = create_lead(1, status: :discarded, discard_reason: 'Sem interesse')

      patch "#{base_path}/leads/#{lead.id}", params: { lead: { status: 'new_lead' } }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect([lead.reload.status, lead.discard_reason]).to eq(['new_lead', nil])
    end
  end

  describe 'POST leads/contacts' do
    it 'cria os contatos da seleção e resume por lead' do
      ok = create_lead(1)
      discarded = create_lead(2, status: :discarded, discard_reason: 'Sem interesse')

      post "#{base_path}/leads/contacts", params: { lead_ids: [ok.id, discarded.id] }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      payload = response.parsed_body['payload']
      expect(payload['created']).to eq([{ 'lead_id' => ok.id, 'contact_id' => ok.reload.contact_id }])
      expect(payload['failed'].map { |row| row['reason_code'] }).to eq(['discarded'])
      expect(account.contacts.count).to eq(1)
    end

    it 'seleção acima do teto responde 422 e nada é criado' do
      ids = Array.new(Autonomia::Prospecting::ContactBatch::MAX_LEADS + 1) { |index| create_lead(index).id }

      post "#{base_path}/leads/contacts", params: { lead_ids: ids }, headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['code']).to eq('prospecting.contact_batch.too_many_leads')
      expect(account.contacts.count).to eq(0)
    end

    it 'quem só vê a prospecção não cria contatos' do
      lead = create_lead(1)

      post "#{base_path}/leads/contacts", params: { lead_ids: [lead.id] },
                                          headers: auth_headers(agent_with(['prospecting_view'])), as: :json

      expect(response).to have_http_status(:unauthorized)
      expect(account.contacts.count).to eq(0)
    end
  end
end

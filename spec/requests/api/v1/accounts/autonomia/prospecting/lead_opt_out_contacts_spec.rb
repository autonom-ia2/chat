require 'rails_helper'

# Recusa da Prospecção gravada no contato (chat#713): quando o lead vira no_consent, o contato dele e os que a recusa
# alcança pelo telefone ou e-mail (ConsentVeto) ficam marcados com a origem 'prospecting', na mesma requisição. O mesmo
# vale para o botão "Não quer ser contatado" (POST leads/:id/consent_refusal). A recusa do lead (consent_refused_at) não
# depende do status: só o "Desfazer" (DELETE) a tira, e então sai só a marca da Prospecção que nenhum outro lead
# recusado sustenta; recusa manual ou de descadastro de e-mail fica. A marca é da conta.
RSpec.describe 'Autonomia prospecting lead refusal on contacts', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(key, phone, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "optout-#{key}", name: "Lead #{key}", phone: phone, country: 'BR',
      status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } },
      **attributes
    )
  end

  def patch_status(lead, status)
    patch "#{base_url}/leads/#{lead.id}", params: { lead: { status: status } }, headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
  end

  def refuse(lead)
    post "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
  end

  def withdraw(lead)
    delete "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:ok)
  end

  def agent_with(permissions)
    user = create(:user, account: account, role: :agent)
    role = create(:custom_role, account: account, permissions: permissions)
    user.account_users.find_by(account: account).update!(custom_role: role)
    user
  end

  def new_contact(phone: nil, email: nil, target_account: account)
    create(:contact, account: target_account, phone_number: phone, email: email)
  end

  it 'lead recusado marca o próprio contato e os contatos da conta com o mesmo telefone ou e-mail' do
    linked = new_contact(phone: '+5531999991001')
    same_phone = new_contact(phone: '+5531999991002')
    same_email = new_contact(email: 'dono@exemplo.com.br')
    lead = create_lead(1, '+5531999991002', contact: linked, enriched_email: 'Dono@Exemplo.com.br')

    patch_status(lead, 'no_consent')

    [linked, same_phone, same_email].each do |contact|
      contact.reload
      expect(contact).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
      expect(contact.opted_out_by_id).to be_nil
    end
  end

  it 'não marca contato de outra conta nem contato sem relação' do
    other_account_contact = new_contact(phone: '+5531999992001', target_account: create(:account))
    unrelated = new_contact(phone: '+5531999992999')
    lead = create_lead(2, '+5531999992001')

    patch_status(lead, 'no_consent')

    expect(other_account_contact.reload).not_to be_opted_out
    expect(unrelated.reload).not_to be_opted_out
  end

  it 'mudança de status que não é recusa não marca ninguém' do
    contact = new_contact(phone: '+5531999993001')
    lead = create_lead(3, '+5531999993001', contact: contact, status: :new_lead)

    patch_status(lead, 'qualified')
    patch_status(lead, 'ready_for_campaign')

    expect(contact.reload).not_to be_opted_out
  end

  it 'não troca a recusa manual que o contato já tinha' do
    contact = new_contact(phone: '+5531999994001')
    contact.opt_out!(source: 'manual', by: admin)
    lead = create_lead(4, '+5531999994001', contact: contact)

    patch_status(lead, 'no_consent')

    expect(contact.reload.opt_out_source).to eq('manual')
    expect(contact.opted_out_by_id).to eq(admin.id)
  end

  it 'desfazer a recusa do lead tira só a marca da Prospecção' do
    linked = new_contact(phone: '+5531999995001')
    manual = new_contact(phone: '+5531999995002')
    unsubscribed = new_contact(email: 'saiu@exemplo.com.br')
    manual.opt_out!(source: 'manual', by: admin)
    unsubscribed.opt_out!(source: 'email_unsubscribe')
    lead = create_lead(5, '+5531999995002', contact: linked, enriched_email: 'saiu@exemplo.com.br')
    patch_status(lead, 'no_consent')
    expect(linked.reload).to be_opted_out

    withdraw(lead)

    expect(linked.reload).not_to be_opted_out
    expect(manual.reload.opt_out_source).to eq('manual')
    expect(unsubscribed.reload.opt_out_source).to eq('email_unsubscribe')
    expect(lead.reload.status).to eq('new_lead')
    expect(lead.consent_refused_at).to be_nil
  end

  it 'a marca fica enquanto outro lead recusado ainda alcança o contato' do
    shared = new_contact(phone: '+5531999996001')
    first = create_lead(6, '+5531999996001')
    second = create_lead(7, '+5531999996001')
    patch_status(first, 'no_consent')
    refuse(second)

    withdraw(first)
    expect(shared.reload).to be_opted_out

    withdraw(second)
    expect(shared.reload).not_to be_opted_out
  end

  # Decisão de 26/09: a recusa é da pessoa e não depende do status. Só o "Desfazer" do lead a tira.
  it 'descartar pelo PATCH o lead recusado mantém a recusa e a marca' do
    contact = new_contact(phone: '+5531999995101')
    lead = create_lead(51, '+5531999995101', contact: contact)
    patch_status(lead, 'no_consent')

    patch "#{base_url}/leads/#{lead.id}", params: { lead: { status: 'discarded', discard_reason: 'Sem interesse' } },
                                          headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig('payload', 'consent_refused_at')).to be_present
    expect(lead.reload.status).to eq('discarded')
    expect(contact.reload.opt_out_source).to eq('prospecting')
  end

  it 'trocar o status do lead recusado pelo PATCH não tira a recusa' do
    contact = new_contact(phone: '+5531999995102')
    lead = create_lead(52, '+5531999995102', contact: contact)
    patch_status(lead, 'no_consent')

    patch_status(lead, 'new_lead')

    expect(lead.reload.consent_refused_at).to be_present
    expect(contact.reload.opt_out_source).to eq('prospecting')
  end

  describe 'botão "Não quer ser contatado"' do
    it 'grava a recusa no lead, com quem marcou, e a marca da Prospecção nos contatos que ela alcança, sem mudar o status' do
      linked = new_contact(phone: '+5531999995201')
      same_phone = new_contact(phone: '+5531999995202')
      lead = create_lead(53, '+5531999995202', contact: linked)

      post "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'consent_refused_at')).to be_present
      lead.reload
      expect(lead.status).to eq('ready_for_campaign')
      expect(lead.consent_refused_by_id).to eq(admin.id)
      [linked, same_phone].each { |contact| expect(contact.reload.opt_out_source).to eq('prospecting') }
    end

    it 'tira o lead do segmento da campanha no job da Prospecção' do
      lead = create_lead(54, '+5531999995203')

      expect { post "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(admin), as: :json }
        .to have_enqueued_job(Autonomia::Prospecting::SegmentRefusalSyncJob).with(account.id, [lead.id])
    end

    it 'desfazer tira a recusa do lead e a marca que só ele sustentava' do
      contact = new_contact(phone: '+5531999995204')
      lead = create_lead(55, '+5531999995204', contact: contact)
      refuse(lead)

      delete "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(admin), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig('payload', 'consent_refused_at')).to be_nil
      expect(lead.reload.consent_refused_by_id).to be_nil
      expect(lead.status).to eq('ready_for_campaign')
      expect(contact.reload).not_to be_opted_out
    end

    it 'sem prospecting_manage não marca nem desfaz' do
      viewer = agent_with(%w[prospecting_view])
      lead = create_lead(56, '+5531999995205')

      post "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(viewer), as: :json
      expect(response).to have_http_status(:unauthorized)
      delete "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(viewer), as: :json
      expect(response).to have_http_status(:unauthorized)
      expect(lead.reload.consent_refused_at).to be_nil
    end

    it 'lead de busca de outro agente não é tocado (404)' do
      agent = agent_with(%w[prospecting_manage])
      other_search = Autonomia::Prospecting::Search.create!(account: account, user: admin, query: 'padaria', provider: 'mock',
                                                            status: 'completed')
      lead = create_lead(57, '+5531999995206', search: other_search)

      post "#{base_url}/leads/#{lead.id}/consent_refusal", headers: auth_headers(agent), as: :json

      expect(response).to have_http_status(:not_found)
      expect(lead.reload.consent_refused_at).to be_nil
    end
  end

  it 'descadastro de e-mail feito depois da recusa da Prospecção continua valendo quando a recusa do lead é desfeita' do
    contact = new_contact(phone: '+5531999997002', email: 'pessoa@exemplo.com.br')
    lead = create_lead(9, '+5531999997002', contact: contact)
    patch_status(lead, 'no_consent')
    refused_at = contact.reload.opted_out_at
    EmailCampaigns::SuppressionRegistry.new(account: account, email: 'Pessoa@Exemplo.com.br')
                                       .block!(reason: 'unsubscribe', source: 'link', event_key: 'unsubscribe:optout-9')
    expect(contact.reload.opt_out_source).to eq('prospecting')

    withdraw(lead)

    contact.reload
    expect(contact).to be_opted_out
    expect(contact.opt_out_source).to eq('email_unsubscribe')
    expect(contact.opted_out_at).to be_within(1.second).of(refused_at)
  end

  it 'supressão de e-mail que não é descadastro não segura a recusa da Prospecção' do
    contact = new_contact(phone: '+5531999997003', email: 'bounce@exemplo.com.br')
    lead = create_lead(10, '+5531999997003', contact: contact)
    patch_status(lead, 'no_consent')
    EmailCampaigns::SuppressionRegistry.new(account: account, email: 'bounce@exemplo.com.br')
                                       .block!(reason: 'hard_bounce', source: 'ses', event_key: 'hard:optout-10')

    withdraw(lead)

    expect(contact.reload).not_to be_opted_out
  end

  it 'telefone vazio não vira telefone recusado: outro contato sem telefone não é marcado' do
    refused = new_contact(email: 'recusou@exemplo.com.br')
    innocent = new_contact(email: 'inocente@exemplo.com.br')
    [refused, innocent].each { |contact| contact.update_columns(phone_number: '') } # rubocop:disable Rails/SkipsModelValidations
    lead = create_lead(11, '+5531999997004', contact: refused)
    patch_status(lead, 'no_consent')

    veto = Autonomia::Prospecting::ConsentVeto.new(account: account)
    expect(veto.contact_vetoed?(innocent.reload)).to be(false)

    other = create_lead(12, nil, enriched_email: 'inocente@exemplo.com.br')
    Autonomia::Prospecting::ContactConverter.new(lead: other, user: admin).perform

    expect(innocent.reload).not_to be_opted_out
  end

  it 'marca o contato com e-mail antigo fora do formato' do
    contact = new_contact(phone: '+5531999997001')
    contact.update_columns(email: 'nao-e-email') # rubocop:disable Rails/SkipsModelValidations
    lead = create_lead(8, '+5531999997001', contact: contact)

    patch_status(lead, 'no_consent')

    expect(contact.reload).to be_opted_out
  end
end

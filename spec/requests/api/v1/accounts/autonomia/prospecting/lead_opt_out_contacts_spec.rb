require 'rails_helper'

# Recusa da Prospecção gravada no contato (chat#713): quando o lead vira no_consent, o contato dele e os que a recusa
# alcança pelo telefone ou e-mail (ConsentVeto) ficam marcados com a origem 'prospecting', na mesma requisição. Quando o
# lead sai de no_consent, sai só a marca da Prospecção que nenhum outro lead recusado sustenta; recusa manual ou de
# descadastro de e-mail fica. A marca é da conta.
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

  it 'lead que sai de no_consent tira só a marca da Prospecção' do
    linked = new_contact(phone: '+5531999995001')
    manual = new_contact(phone: '+5531999995002')
    unsubscribed = new_contact(email: 'saiu@exemplo.com.br')
    manual.opt_out!(source: 'manual', by: admin)
    unsubscribed.opt_out!(source: 'email_unsubscribe')
    lead = create_lead(5, '+5531999995002', contact: linked, enriched_email: 'saiu@exemplo.com.br')
    patch_status(lead, 'no_consent')
    expect(linked.reload).to be_opted_out

    patch_status(lead, 'new_lead')

    expect(linked.reload).not_to be_opted_out
    expect(manual.reload.opt_out_source).to eq('manual')
    expect(unsubscribed.reload.opt_out_source).to eq('email_unsubscribe')
  end

  it 'a marca fica enquanto outro lead recusado ainda alcança o contato' do
    shared = new_contact(phone: '+5531999996001')
    first = create_lead(6, '+5531999996001')
    second = create_lead(7, '+5531999996001')
    patch_status(first, 'no_consent')
    patch_status(second, 'no_consent')

    patch_status(first, 'new_lead')
    expect(shared.reload).to be_opted_out

    patch_status(second, 'new_lead')
    expect(shared.reload).not_to be_opted_out
  end

  it 'marca o contato com e-mail antigo fora do formato' do
    contact = new_contact(phone: '+5531999997001')
    contact.update_columns(email: 'nao-e-email') # rubocop:disable Rails/SkipsModelValidations
    lead = create_lead(8, '+5531999997001', contact: contact)

    patch_status(lead, 'no_consent')

    expect(contact.reload).to be_opted_out
  end
end

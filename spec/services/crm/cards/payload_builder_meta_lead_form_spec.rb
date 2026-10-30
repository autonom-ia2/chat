require 'rails_helper'

# Card de quem chegou pelo formulário do anúncio da Meta (#2195): a origem aparece a todos que veem o card; as respostas
# (nome, telefone, e-mail) só a quem vê o contato inteiro, como o resto do contato (#1849).
RSpec.describe Crm::Cards::PayloadBuilder do
  around do |example|
    with_modified_env CRM_KANBAN_ENABLED: 'true' do
      example.run
    end
  end

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    origem = { 'form_name' => 'Orçamento', 'ad_name' => 'Carrossel', 'fields' => [{ 'key' => 'email', 'value' => 'ana@example.com' }] }
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Ana', metadata: { 'meta_lead_form' => origem })
  end

  def payload(full:)
    allow(Crm::Cards::ContactReading).to receive(:full?).and_return(full)
    described_class.new(card, user: admin, account_user: admin.account_users.find_by(account: account)).perform
  end

  it 'quem vê o contato inteiro recebe a origem e as respostas' do
    expect(payload(full: true)[:metadata]['meta_lead_form']).to include('form_name' => 'Orçamento', 'fields' => be_present)
  end

  it 'quem não vê a base de contatos recebe só a origem, sem as respostas' do
    origem = payload(full: false)[:metadata]['meta_lead_form']

    expect(origem).to eq('form_name' => 'Orçamento', 'ad_name' => 'Carrossel')
  end
end

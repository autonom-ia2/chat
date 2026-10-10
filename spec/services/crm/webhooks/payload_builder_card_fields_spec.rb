require 'rails_helper'

# Multifunil 6a (#1146): os campos próprios do card saem para a integração (n8n, webhook) só com o opt-in de dados
# pessoais, o mesmo do e-mail e do telefone do contato: campo de card pode guardar CPF ou placa.
RSpec.describe Crm::Webhooks::PayloadBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Onix', custom_attributes: { 'placa' => 'ABC1D23' })
  end

  def data(include_contact_pii:)
    described_class.new(card: card, event: 'crm.card.updated', event_id: 'evt-1', include_contact_pii: include_contact_pii).perform[:data]
  end

  it 'manda os campos do card com o opt-in de dados pessoais' do
    expect(data(include_contact_pii: true)[:custom_attributes]).to eq('placa' => 'ABC1D23')
  end

  it 'sem o opt-in, os campos do card ficam de fora' do
    expect(data(include_contact_pii: false)).not_to have_key(:custom_attributes)
  end
end

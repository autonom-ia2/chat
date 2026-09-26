require 'rails_helper'

# Criar contatos em lote (#732, item 10): o mesmo ContactConverter do botão do lead, um lead por vez, e um resumo com
# criados, já existentes e falhas com motivo. Lead descartado não vira contato.
RSpec.describe Autonomia::Prospecting::ContactBatch do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }

  def create_lead(index, target_account: account, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: target_account, provider: 'mock', provider_place_id: "contact-batch-#{target_account.id}-#{index}",
      name: "Empresa #{index}", phone: "+55 31 99999-10#{index.to_s.rjust(2, '0')}", country: 'BR', **attributes
    )
  end

  def perform(lead_ids)
    described_class.new(account: account, user: user, lead_ids: lead_ids).perform
  end

  it 'cria um contato por lead e vincula cada contato ao seu lead' do
    leads = Array.new(3) { |index| create_lead(index) }

    result = perform(leads.map(&:id))

    expect([result.created.size, result.existing.size, result.failed.size]).to eq([3, 0, 0])
    leads.each do |lead|
      item = result.created.find { |row| row[:lead_id] == lead.id }
      expect(lead.reload.contact_id).to eq(item[:contact_id])
    end
    expect(account.contacts.count).to eq(3)
  end

  it 'lead que já tem contato volta como já existente, sem duplicar' do
    lead = create_lead(1)
    Autonomia::Prospecting::ContactConverter.new(lead: lead, user: user).perform

    result = perform([lead.id])

    expect(result.existing).to eq([{ lead_id: lead.id, contact_id: lead.reload.contact_id }])
    expect(account.contacts.count).to eq(1)
  end

  it 'lead descartado e lead de outra conta falham com o motivo, e os outros seguem' do
    ok = create_lead(1)
    discarded = create_lead(2, status: :discarded, discard_reason: 'Fora do perfil')
    foreign = create_lead(3, target_account: other_account)

    result = perform([ok.id, discarded.id, foreign.id])

    expect(result.created.map { |row| row[:lead_id] }).to eq([ok.id])
    expect(result.failed.map { |row| [row[:lead_id], row[:reason_code]] }).to eq([[discarded.id, 'discarded'], [foreign.id, 'not_found']])
    expect(result.failed.first[:message]).to eq(I18n.t('autonomia.prospecting.contact_batch.failures.discarded'))
    expect(discarded.reload.contact_id).to be_nil
  end

  it 'recusa seleção vazia e acima do teto' do
    expect { perform([]) }.to raise_error(described_class::NoLeads)
    expect { perform((1..(described_class::MAX_LEADS + 1)).to_a) }.to raise_error(described_class::TooManyLeads)
  end
end

require 'rails_helper'

# Descartar leads (#732, item 10): no painel e em lote, sempre com motivo. Lead de outra conta não é tocado e volta como
# não encontrado, igual a lead que não existe.
RSpec.describe Autonomia::Prospecting::LeadDiscard do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }

  def create_lead(index, target_account: account, **attributes)
    Autonomia::Prospecting::Lead.create!(
      account: target_account, provider: 'mock', provider_place_id: "discard-#{target_account.id}-#{index}", name: "Empresa #{index}",
      **attributes
    )
  end

  def perform(lead_ids, reason = 'Fora do perfil')
    described_class.new(account: account, lead_ids: lead_ids, reason: reason).perform
  end

  it 'descarta os leads da conta com o motivo e devolve os leads gravados' do
    first, second = Array.new(2) { |index| create_lead(index) }

    result = perform([first.id, second.id], '  Fora do perfil  ')

    expect(result.leads.map(&:id)).to contain_exactly(first.id, second.id)
    expect([first.reload, second.reload].map { |lead| [lead.status, lead.discard_reason] })
      .to eq([['discarded', 'Fora do perfil'], ['discarded', 'Fora do perfil']])
    expect(result.missing_lead_ids).to eq([])
  end

  it 'lead de outra conta fica como estava e sai como não encontrado' do
    own = create_lead(1)
    foreign = create_lead(2, target_account: other_account)

    result = perform([own.id, foreign.id])

    expect(result.missing_lead_ids).to eq([foreign.id])
    expect(foreign.reload.status).to eq('new_lead')
  end

  it 'lead já descartado recebe o motivo novo' do
    lead = create_lead(1, status: :discarded, discard_reason: 'Antigo')

    perform([lead.id], 'Novo motivo')

    expect(lead.reload.discard_reason).to eq('Novo motivo')
  end

  it 'sem motivo não descarta nada' do
    lead = create_lead(1)

    expect { perform([lead.id], '   ') }.to raise_error(described_class::MissingReason)
    expect(lead.reload.status).to eq('new_lead')
  end

  it 'motivo longo demais é recusado' do
    lead = create_lead(1)

    expect { perform([lead.id], 'a' * (described_class::MAX_REASON_LENGTH + 1)) }.to raise_error(described_class::ReasonTooLong)
  end

  it 'recusa seleção vazia e seleção acima do teto' do
    expect { perform([]) }.to raise_error(described_class::NoLeads)
    expect { perform((1..(described_class::MAX_LEADS + 1)).to_a) }.to raise_error(described_class::TooManyLeads)
  end
end

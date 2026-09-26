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

  # chat#713: descartar lead recusado passa pelo ContactOptOutSync. A marca da Prospecção sai do contato, a menos que
  # outro lead recusado da conta ainda o alcance.
  context 'when o lead descartado estava em no_consent' do
    def refused_lead(index, phone, contact: nil)
      lead = create_lead(index, phone: phone, country: 'BR', contact: contact,
                                metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } })
      Autonomia::Prospecting::ContactOptOutSync.new(account: account).update_lead!(lead, status: :no_consent)
      lead
    end

    it 'tira a marca da Prospecção do contato' do
      contact = create(:contact, account: account, phone_number: '+5531999981001')
      lead = refused_lead(1, '+5531999981001', contact: contact)
      expect(contact.reload.opt_out_source).to eq('prospecting')

      perform([lead.id])

      expect(lead.reload.status).to eq('discarded')
      expect(contact.reload).not_to be_opted_out
    end

    it 'mantém a marca enquanto outro lead recusado alcança o contato' do
      contact = create(:contact, account: account, phone_number: '+5531999981002')
      lead = refused_lead(2, '+5531999981002')
      refused_lead(3, '+5531999981002')
      expect(contact.reload.opt_out_source).to eq('prospecting')

      perform([lead.id])

      expect(contact.reload).to be_opted_out
      expect(contact.opt_out_source).to eq('prospecting')
    end

    it 'descartar juntos os leads recusados que dividem o contato tira a marca' do
      contact = create(:contact, account: account, phone_number: '+5531999981004')
      first = refused_lead(5, '+5531999981004')
      second = refused_lead(6, '+5531999981004')
      expect(contact.reload.opt_out_source).to eq('prospecting')

      perform([first.id, second.id])

      expect(contact.reload).not_to be_opted_out
    end

    it 'não tira recusa manual' do
      contact = create(:contact, account: account, phone_number: '+5531999981003')
      contact.opt_out!(source: 'manual')
      lead = refused_lead(4, '+5531999981003', contact: contact)

      perform([lead.id])

      expect(contact.reload.opt_out_source).to eq('manual')
    end
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

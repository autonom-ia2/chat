require 'rails_helper'

# #2775, revisão item 6: quem entrou na lista entre a leitura de members e a trava (outra aba, outra pessoa) é pulado
# pelo AudienceMembership; o lead dele não pode aparecer como "entrou", e sim em left_out com already_in_list.
RSpec.describe Autonomia::Prospecting::LeadsIntoAudience do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "into-#{index}", name: "Empresa #{index}",
                                         phone: "+55 31 99999-42#{index.to_s.rjust(2, '0')}", country: 'BR')
  end

  def save(leads)
    Autonomia::Prospecting::AudienceFromLeads.new(account: account, user: admin, lead_ids: leads.map(&:id), name: 'Lista').perform.audience
  end

  def service(audience, leads)
    described_class.new(account: account, user: admin, lead_ids: leads.map(&:id), audience: audience).tap do |item|
      # A leitura de members veio antes de o contato entrar: ela não o vê.
      allow(item).to receive(:members).and_return(Set.new)
    end
  end

  it 'o lead pulado pelo AudienceMembership sai de entered e vai para left_out como already_in_list' do
    first = create_lead(1)
    audience = save([first])
    second = create_lead(2)

    result = service(audience, [first, second]).perform

    expect(result.entered_lead_ids).to eq([second.id])
    expect(result.left_out.map { |item| [item[:lead_id], item[:reason_code]] }).to eq([[first.id, 'already_in_list']])
    expect(audience.campaign_import_rows.count).to eq(2)
  end

  it 'quando todos foram pulados: all_already_in_list, com os contatos já gravados' do
    first = create_lead(1)
    audience = save([first])

    expect { service(audience, [first]).perform }.to raise_error do |error|
      expect(error.class.name).to eq('Autonomia::Prospecting::AudienceFromLeads::Error')
      expect(error.message).to eq('all_already_in_list')
      expect(error.contacts_saved).to be(true)
      expect(error.left_out.map { |item| item[:reason_code] }).to eq(['already_in_list'])
    end
  end
end

require 'rails_helper'

# #2775, item 16: o motivo da régua de todo Público (ConversationAudience::Reach.reason_for) que o mapa não conhece
# nunca deixa o contato entrar calado. 'bloqueado' é o motivo que a #2733 cria.
RSpec.describe Autonomia::Prospecting::AudienceFromLeads do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(index)
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: "from-#{index}", name: "Empresa #{index}",
                                         phone: "+55 31 99999-43#{index.to_s.rjust(2, '0')}", country: 'BR')
  end

  def perform_with_reason(reason)
    lead = create_lead(1)
    allow(ConversationAudience::Reach).to receive(:reason_for).and_return(reason)
    described_class.new(account: account, user: admin, lead_ids: [lead.id], name: 'Lista').perform
  rescue StandardError => e
    e
  end

  it 'motivo que o mapa não conhece: o contato não entra e sai em left_out como unreachable' do
    error = perform_with_reason('motivo_novo')

    expect(error.class.name).to eq('Autonomia::Prospecting::AudienceFromLeads::Error')
    expect(error.message).to eq('no_rows')
    expect(error.left_out.map { |item| item[:reason_code] }).to eq(['unreachable'])
    expect(error.left_out.first[:message]).to eq(I18n.t('autonomia.prospecting.audience.left_out.unreachable'))
    expect(account.campaign_imports.count).to eq(0)
  end

  it "'bloqueado' (#2733): o contato não entra e sai em left_out como blocked" do
    error = perform_with_reason('bloqueado')

    expect(error.left_out.map { |item| item[:reason_code] }).to eq(['blocked'])
    expect(error.left_out.first[:message]).to eq(I18n.t('autonomia.prospecting.audience.left_out.blocked'))
    expect(account.campaign_imports.count).to eq(0)
  end

  it 'sem motivo, o contato entra' do
    result = perform_with_reason(nil)

    expect(result.entered_lead_ids.size).to eq(1)
    expect(result.left_out).to eq([])
  end
end

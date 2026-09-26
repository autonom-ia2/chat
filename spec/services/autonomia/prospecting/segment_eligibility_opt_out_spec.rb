require 'rails_helper'

# A recusa gravada no contato (chat#713), de qualquer origem, tira o lead do segmento como opt_out.
RSpec.describe Autonomia::Prospecting::SegmentEligibility do
  let(:account) { create(:account) }
  let(:eligibility) { described_class.new(account: account, user: nil) }
  let(:contact) { create(:contact, account: account, phone_number: '+5531999998001') }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'eligibility-optout', name: 'Lead', phone: '+5531999998001',
      country: 'BR', status: :ready_for_campaign, contact: contact,
      metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5531999998001' } }
    )
  end

  it 'contato sem recusa segue elegível' do
    expect(eligibility.block_reason(lead)).to be_nil
  end

  %w[manual email_unsubscribe prospecting].each do |source|
    it "contato com recusa de origem #{source} fica fora como opt_out" do
      contact.opt_out!(source: source)

      expect(eligibility.block_reason(lead)).to eq('opt_out')
    end
  end

  # A recusa do lead não depende do status (26/09): quem recusou pelo botão fica fora, e veta o outro lead do número.
  it 'lead recusado pelo botão, com qualquer status, fica fora como opt_out e veta outro lead do mesmo número' do
    lead.update!(consent_refused_at: Time.current)
    other = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'eligibility-optout-2', name: 'Outro', phone: '+5531999998001',
      country: 'BR', status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5531999998001' } }
    )

    expect(eligibility.block_reason(lead)).to eq('opt_out')
    expect(eligibility.lead_ready?(lead)).to be(false)
    expect(eligibility.block_reason(other)).to eq('opt_out')
  end

  it 'contato bloqueado continua com o motivo de bloqueio' do
    contact.update!(blocked: true)
    contact.opt_out!(source: 'manual')

    expect(eligibility.block_reason(lead)).to eq('contact_blocked')
  end
end

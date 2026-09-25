require 'rails_helper'

# Motivo por lead bloqueado na campanha (#680, ACAO-26/27): quem não entra diz por quê, e contato bloqueado ou que
# pediu para parar nunca recebe a etiqueta da campanha.
RSpec.describe Autonomia::Prospecting::CampaignSegmentBuilder do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: user, name: 'Selecao') }

  def add_lead(name:, phone: '+5531999990001', status: :ready_for_campaign, verified: true, discard_reason: nil)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "place-#{name}", name: name, phone: phone,
      country: 'BR', status: status, discard_reason: discard_reason,
      metadata: verified ? { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } } : {}
    )
    list.list_leads.create!(account: account, lead: lead)
    lead
  end

  def reasons(result)
    result.blocked_leads.to_h { |row| [row[:lead].name, row[:reason_code]] }
  end

  it 'dá o motivo de cada lead bloqueado e só etiqueta quem pode receber' do
    add_lead(name: 'Pronto', phone: '+5531999990001')
    add_lead(name: 'Descartado', phone: '+5531999990002', status: :discarded, discard_reason: 'Fora do perfil')
    add_lead(name: 'Sem consentimento', phone: '+5531999990003', status: :no_consent)
    add_lead(name: 'Sem telefone', phone: nil, verified: false)
    add_lead(name: 'Sem WhatsApp', phone: '+5531999990005', verified: false)
    add_lead(name: 'Nao pronto', phone: '+5531999990006', status: :qualified)
    blocked = add_lead(name: 'Bloqueado', phone: '+5531999990007')
    account.contacts.create!(name: 'Bloqueado', phone_number: '+5531999990007', blocked: true)
    opted_out = add_lead(name: 'Pediu para parar', phone: '+5531999990008')
    opted_contact = account.contacts.create!(name: 'Pediu para parar', phone_number: '+5531999990008')
    pipeline, stage = create_crm_pipeline(account: account, user: user)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', contact: opted_contact,
                              metadata: { 'ai' => { 'auto_followup_state' => { 'opted_out' => true } } })

    result = described_class.new(list: list, user: user, segment_name: 'Selecao').perform

    expect(result.eligible_leads.map(&:name)).to eq(['Pronto'])
    expect(reasons(result)).to eq(
      'Descartado' => 'discarded', 'Sem consentimento' => 'opt_out', 'Sem telefone' => 'no_phone',
      'Sem WhatsApp' => 'no_whatsapp', 'Nao pronto' => 'not_ready', 'Bloqueado' => 'contact_blocked',
      'Pediu para parar' => 'opt_out'
    )
    label = result.label.title
    expect(account.contacts.find_by(phone_number: '+5531999990007').label_list).not_to include(label)
    expect(opted_contact.reload.label_list).not_to include(label)
    expect(blocked.reload.contact).to be_nil
    expect(opted_out.reload.contact).to be_nil
  end

  # A guarda olha o mesmo contato que vai receber a etiqueta: o ContactConverter acha pelo WhatsApp verificado (que pode
  # ser outro número), pelo identificador e pelo e-mail, não só pelo telefone do Google.
  describe 'contato bloqueado achado por outro caminho que não o telefone do lead' do
    it 'WhatsApp verificado diferente do telefone, num contato bloqueado: fica fora e não é etiquetado' do
      add_lead(name: 'Pronto', phone: '+5531999990001')
      lead = add_lead(name: 'Loja', phone: '+5531999990002')
      lead.update!(metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => '+5531988880001' } })
      blocked = account.contacts.create!(name: 'Bloqueado', phone_number: '+5531988880001', blocked: true)

      result = described_class.new(list: list, user: user, segment_name: 'Selecao').perform

      expect(reasons(result)).to eq('Loja' => 'contact_blocked')
      expect(blocked.reload.label_list).not_to include(result.label.title)
      expect(lead.reload.contact).to be_nil
    end

    it 'e-mail do lead num contato bloqueado: fica fora e não é etiquetado' do
      add_lead(name: 'Pronto', phone: '+5531999990001')
      lead = add_lead(name: 'Loja', phone: '+5531999990002')
      lead.update!(enriched_email: 'x@loja.com.br')
      blocked = account.contacts.create!(name: 'Bloqueado', email: 'x@loja.com.br', blocked: true)

      result = described_class.new(list: list, user: user, segment_name: 'Selecao').perform

      expect(reasons(result)).to eq('Loja' => 'contact_blocked')
      expect(blocked.reload.label_list).not_to include(result.label.title)
    end
  end

  it 'sem nenhum elegível recusa, e ainda assim diz o motivo de cada bloqueado' do
    add_lead(name: 'Sem WhatsApp', phone: '+5531999990005', verified: false)
    builder = described_class.new(list: list, user: user)

    expect { builder.perform }.to raise_error(described_class::Error, 'prospecting.campaign.no_eligible_leads')
    expect(builder.blocked_details.map { |row| row[:reason_code] }).to eq(['no_whatsapp'])
  end
end

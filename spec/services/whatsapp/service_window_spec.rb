require 'rails_helper'

# #1335: a janela de atendimento de 24 h por contato e caixa, em lote (campanha) e para uma pessoa (no envio).
RSpec.describe Whatsapp::ServiceWindow do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:other_inbox) { create(:channel_whatsapp, account: account, sync_templates: false, validate_provider_config: false).inbox }
  let(:now) { Time.zone.parse('2026-10-13 12:00') }
  let(:ana) { create(:contact, account: account) }
  let(:bia) { create(:contact, account: account) }
  let(:caio) { create(:contact, account: account) }

  def incoming(contact, at:, box: inbox, type: :incoming)
    conversation = create(:conversation, account: account, inbox: box, contact: contact)
    create(:message, account: account, inbox: box, conversation: conversation, sender: contact, message_type: type, created_at: at)
  end

  it 'conta só quem mandou mensagem a esta caixa nas últimas 24 horas' do
    incoming(ana, at: now - 3.hours)
    incoming(bia, at: now - 25.hours)
    incoming(caio, at: now - 1.hour, box: other_inbox)
    incoming(caio, at: now - 2.hours, type: :outgoing)

    window = described_class.new(inbox: inbox, now: now)

    expect(window.open_contact_ids([ana.id, bia.id, caio.id])).to eq(Set[ana.id])
    expect(window.open?(ana)).to be(true)
    expect(window.open?(bia)).to be(false)
    expect(window.open?(caio)).to be(false)
  end

  it 'diz quantos saem da janela nas próximas 2 horas' do
    incoming(ana, at: now - 23.hours)
    incoming(bia, at: now - 5.hours)

    expect(described_class.new(inbox: inbox, now: now).closing_soon_count([ana.id, bia.id])).to eq(1)
  end

  it 'lê em lotes sem perder ninguém' do
    stub_const("#{described_class}::BATCH_SIZE", 1)
    incoming(ana, at: now - 1.hour)
    incoming(bia, at: now - 2.hours)

    expect(described_class.new(inbox: inbox, now: now).open_contact_ids([ana.id, bia.id, caio.id])).to eq(Set[ana.id, bia.id])
  end
end

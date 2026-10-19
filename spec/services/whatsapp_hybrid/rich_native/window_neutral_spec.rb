require 'rails_helper'
require_relative '../rich_native_context'

# chat#1709: as mensagens recebidas que abrem a janela de 24 h, sem as neutras (o voto do plano B). Contrato público do
# Followup IA (#1766).
describe WhatsappHybrid::RichNative::WindowNeutral do
  include_context 'with a hybrid inbox for rich native'

  def incoming(neutral: false)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, account: account, inbox: inbox, sender: contact,
                     additional_attributes: neutral ? { described_class::KEY => true } : {})
  end

  describe '.opening' do
    it 'drops the neutral incoming message and keeps the real one, on a chained relation' do
      real = incoming
      neutral = incoming(neutral: true)

      opening = described_class.opening(conversation.messages.incoming)

      expect(opening).to be_a(ActiveRecord::Relation)
      expect(opening.pluck(:id)).to eq([real.id])
      expect(opening.where(id: neutral.id)).to be_empty
      expect(described_class.opening(conversation.messages.incoming.reorder(id: :desc)).limit(1).pick(:id)).to eq(real.id)
    end
  end

  it 'keeps the 24 h window closed after only a neutral message, through the same rule' do
    incoming(neutral: true)

    expect(Conversations::MessageWindowService.new(conversation.reload).can_reply?).to be(false)

    incoming
    expect(Conversations::MessageWindowService.new(conversation.reload).can_reply?).to be(true)
  end
end

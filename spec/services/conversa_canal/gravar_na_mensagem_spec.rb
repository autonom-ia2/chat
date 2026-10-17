require 'rails_helper'

# #1702: a mudança da pele numa mensagem que já existe não pode cair na anti-enxurrada do Message, que conta
# mensagens criadas no último minuto e roda em todo save.
describe ConversaCanal::GravarNaMensagem do
  let(:conversation) { create(:conversation) }
  let!(:message) do
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox, source_id: 'wamid.ocupada')
  end

  before { allow(Limits).to receive(:conversation_message_per_minute_limit).and_return(1) }

  it 'shows that a regular update is refused in a busy conversation' do
    expect { message.update!(content_attributes: { 'reactions' => [] }) }.to raise_error(ActiveRecord::RecordInvalid)
  end

  it 'records the change in a busy conversation and still announces message_updated' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    described_class.atualizar!(message, content_attributes: { 'played_at' => '2026-10-16T12:00:00Z' })

    expect(message.reload.content_attributes['played_at']).to eq('2026-10-16T12:00:00Z')
    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::MESSAGE_UPDATED, anything, hash_including(message: message))
  end

  it 'lets the contact reaction through in a busy conversation' do
    Whatsapp::ReactionRecorder.new(inbox: conversation.inbox, reacted_source_id: 'wamid.ocupada', emoji: '👍').perform

    expect(message.reload.content_attributes['reactions'].sole['emoji']).to eq('👍')
  end
end

require 'rails_helper'
require_relative 'inbound_context'

# chat#1709 (rodada de correção, itens 14 e 15): o voto e a resposta ao convite como as IAs os leem. O `content` do turno
# é só a escolha ("Votou: Não"); a pergunta fica em `c2y_ai_turn.question`, e o contexto das IAs (resposta do agente, CRM,
# assunto) lê o texto completo, com a escolha que não vale mais marcada.
describe Waha::RichNative::AiChoiceText do
  include_context 'with a waha inbox and its connector'

  let(:poll) do
    create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Quer cancelar?')
  end

  def vote!(titles)
    poll.update_column(:content_attributes, { 'poll_votes' => [{ 'sender_type' => 'Contact', 'sender_id' => conversation.contact_id, # rubocop:disable Rails/SkipsModelValidations
                                                                 'options' => titles }] })
  end

  # O turno como Waha::RichNative::PollVote.record_vote! o grava.
  def turn(titles)
    message = conversation.messages.new(account: account, inbox: inbox, message_type: :incoming, sender: conversation.contact)
    Waha::RichNative::AiTurn.record!(message, Waha::RichNative::AiTurn.poll_text(account, poll, titles),
                                     Waha::RichNative::AiTurn.choice('poll_vote', poll, titles))
    Waha::RichNative::InternalWrite.mark!(message).save!
    message.reload
  end

  it 'keeps only the choice in the content (no "cancelar" for an automation) and the question in content_attributes' do
    message = turn(['Não'])

    expect(message.content).to eq('Votou: Não')
    expect(message.content_attributes['c2y_ai_turn']).to include('question' => 'Quer cancelar?', 'choice' => ['Não'])
  end

  it 'gives the AI the full text while the choice still counts, and marks it once taken back' do
    vote!(['Não'])
    message = turn(['Não'])

    expect(described_class.for(message)).to eq("Votou na enquete 'Quer cancelar?': Não")

    vote!([])
    expect(described_class.for(message))
      .to eq("Votou na enquete 'Quer cancelar?': Não (o cliente retirou ou trocou esta escolha depois; ela não vale mais)")
    expect(described_class.for(create(:message, account: account, conversation: conversation, inbox: inbox, content: 'oi'))).to be_nil
  end

  it 'feeds the CRM context and the subject reader with the full text and the stale mark' do
    vote!(['Sim'])
    stale = turn(['Não'])

    builder_text = Crm::Ai::ContextBuilder.new(card: nil).send(:message_content, stale)
    estado = Autonomia::Decisores::Estado.new(conversation: conversation, message: stale, leituras: %w[mensagens_com_respostas])

    expect(builder_text).to end_with('(o cliente retirou ou trocou esta escolha depois; ela não vale mais)')
    expect(estado.conversa[:messages].last).to eq("Customer: #{builder_text}")
    expect(stale.reload.content).to eq('Votou: Não')
  end

  it 'reads the event reply with the event name' do
    event = create(:message, account: account, conversation: conversation, inbox: inbox, message_type: :outgoing, content: 'Vistoria')
    message = conversation.messages.new(account: account, inbox: inbox, message_type: :incoming, sender: conversation.contact)
    Waha::RichNative::AiTurn.record!(message, Waha::RichNative::AiTurn.event_text(account, event, 'going'),
                                     Waha::RichNative::AiTurn.choice('event_response', event, 'going'))
    event.update_column(:content_attributes, { 'event_responses' => [{ 'sender_type' => 'Contact', 'sender_id' => conversation.contact_id, # rubocop:disable Rails/SkipsModelValidations
                                                                       'response' => 'going' }] })
    Waha::RichNative::InternalWrite.mark!(message).save!

    expect(message.reload.content).to eq('Respondeu ao convite: Vou')
    expect(described_class.for(message)).to eq("Respondeu ao convite 'Vistoria': Vou")
  end
end

require 'rails_helper'
require_relative '../../../services/waha/rich_native/inbound_context'

# chat#1709 (rodada de correção, item 12, e revisão do estresse): a reação e a edição pelo painel vão ao conector por um
# job que sabe se o evento chegou e que monta o evento NA HORA DA ENTREGA, do estado atual. Falha passageira: nova
# tentativa; esgotada, uma nota privada na conversa, sem desfazer a mudança. A ação mais nova supera as anteriores.
describe Waha::RichNative::MessageActionDeliveryJob do
  include ActiveJob::TestHelper
  include_context 'with a waha inbox and its connector'

  let(:reaction) { Waha::RichNative::MessageActions::REACTION_EVENT }
  let(:edit) { Waha::RichNative::MessageActions::EDIT_EVENT }
  let(:message) do
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: inbox, account: account)
  end
  let(:delivered) { [] }
  # Cada pedido c2y_* que chegou ao conector, aceito ou não.
  let(:attempts) { [] }

  before do
    channel.update!(secret: 'segredo-de-teste')
    allow(Waha::RichNative::OutgoingHints).to receive(:whatsapp_text) { |text, _message = nil| "WA[#{text}]" }
  end

  # O conector: cada pedido, com o corpo; `failures` = quantas respostas 503 antes de aceitar.
  def connector!(failures: 0)
    calls = 0
    allow(SafeFetch).to receive(:fetch) do |url, **options|
      next unless url == channel.webhook_url && options[:body]

      payload = JSON.parse(options[:body])
      next unless payload['event'].to_s.start_with?('c2y_')

      calls += 1
      attempts << payload
      raise SafeFetch::HttpError.new('503 Service Unavailable', status: 503) if calls <= failures

      delivered << payload
    end
  end

  def notes
    conversation.messages.where(private: true)
  end

  # Roda a fila até esvaziar (as novas tentativas entram nela), como o Sidekiq faria com o tempo.
  def drain!
    10.times do
      break if enqueued_jobs.empty?

      perform_enqueued_jobs
    end
  end

  # A primeira entrega roda (e falha, se o conector mandar) antes da ação seguinte do atendente; a nova tentativa fica
  # na fila.
  def first_attempt!(target, event)
    enqueued_jobs.clear
    described_class.request!(target, event)
    perform_enqueued_jobs
  end

  it 'posts the signed event with the current state' do
    connector!
    Waha::RichNative::Reactions.apply!(message, emoji: '👍', author: Waha::RichNative::Reactions.business_author(agent.id))

    perform_enqueued_jobs { described_class.request!(message, reaction) }

    expect(delivered.sole).to include('event' => reaction, 'id' => message.id, 'c2y_reaction' => { 'emoji' => '👍' })
    expect(notes).to be_empty
  end

  describe 'C5: a 503 on the first delivery and two actions in a row' do
    it 'the reaction that reaches the connector last is the current one (❤️), never the old one' do
      connector!(failures: 1)
      business = Waha::RichNative::Reactions.business_author(agent.id)

      Waha::RichNative::Reactions.apply!(message, emoji: '👍', author: business)
      first_attempt!(message, reaction)
      Waha::RichNative::Reactions.apply!(message, emoji: '❤️', author: business)
      described_class.request!(message, reaction)
      drain!

      expect(attempts.size).to eq(2) # o 503 da primeira (👍) e a entrega do estado atual; a tentativa velha não reenviou
      expect(delivered.map { |payload| payload.dig('c2y_reaction', 'emoji') }).to eq(['❤️'])
      expect(notes).to be_empty
    end

    it 'the edit that reaches the connector last is the current text (v2)' do
      connector!(failures: 1)
      ours = create(:message, message_type: :outgoing, content: 'v0', conversation: conversation, inbox: inbox, account: account,
                              sender: agent)

      Waha::RichNative::Edits.apply!(ours, content: 'v1', author: Waha::RichNative::Edits.user_author(agent.id))
      first_attempt!(ours, edit)
      Waha::RichNative::Edits.apply!(ours, content: 'v2', author: Waha::RichNative::Edits.user_author(agent.id))
      described_class.request!(ours, edit)
      drain!

      expect(delivered.map { |payload| payload.dig('c2y_edit', 'waha_text') }).to eq(['WA[v2]'])
    end

    it 'the last state still arrives when only the newest action hits the transient failure' do
      business = Waha::RichNative::Reactions.business_author(agent.id)
      connector!
      Waha::RichNative::Reactions.apply!(message, emoji: '👍', author: business)
      perform_enqueued_jobs { described_class.request!(message, reaction) }

      connector!(failures: 2)
      Waha::RichNative::Reactions.apply!(message, emoji: '', author: business)
      perform_enqueued_jobs { described_class.request!(message, reaction) }

      expect(delivered.map { |payload| payload.dig('c2y_reaction', 'emoji') }).to eq(['👍', ''])
    end
  end

  it 'retries a failure and, when the attempts run out, leaves a private note and keeps the reaction' do
    connector!(failures: described_class::ATTEMPTS)
    Waha::RichNative::Reactions.apply!(message, emoji: '👍', author: Waha::RichNative::Reactions.business_author(agent.id))

    perform_enqueued_jobs { described_class.request!(message, reaction) }

    expect(delivered).to be_empty
    note = notes.sole
    expect(note.content).to eq('A reação não chegou ao WhatsApp do cliente. Ela ficou registrada só aqui no chat2you.')
    expect(note).to be_outgoing
    expect(message.reload.content_attributes['reactions']).to be_present
  end

  it 'says the edit did not arrive, for the edit event' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'timeout')

    perform_enqueued_jobs { described_class.request!(message, edit) }

    expect(notes.sole.content).to eq('A edição não chegou ao WhatsApp do cliente. O cliente continua vendo o texto anterior.')
  end

  # Rodada de correção, itens 4 e 5: erro que não passa com o tempo vai direto ao aviso; caixa sem webhook também avisa.
  { 'endereço recusado' => SafeFetch::UnsafeUrlError.new('privado'), 'endereço inválido' => SafeFetch::InvalidUrlError.new('x'),
    'recusa 4xx' => SafeFetch::HttpError.new('401 Unauthorized', status: 401) }.each do |caso, erro|
    it "does not retry a permanent failure (#{caso}) and leaves the note at once" do
      allow(SafeFetch).to receive(:fetch).and_raise(erro)

      perform_enqueued_jobs { described_class.request!(message, reaction) }

      expect(SafeFetch).to have_received(:fetch).with(channel.webhook_url, hash_including(body: include('c2y_message_reaction'))).once
      expect(notes.count).to eq(1)
    end
  end

  it 'leaves the note when the inbox has no webhook address' do
    allow(SafeFetch).to receive(:fetch)
    channel.update!(webhook_url: '')

    described_class.new(message.id, reaction, 'D4').tap { |job| job.arguments = [message.id, reaction, 'D4'] }
                   .perform(message.id, reaction, 'D4')

    expect(SafeFetch).not_to have_received(:fetch)
    expect(notes.sole.content).to start_with('A reação não chegou')
  end
end

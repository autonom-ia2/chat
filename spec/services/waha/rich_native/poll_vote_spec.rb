require 'rails_helper'

# chat#1709 (fase 3): enquete nativa pela caixa WAHA comum (pedido `sendPoll` no webhook) e o voto de volta
# (`waha_poll_vote`, Waha::RichNative::Inbound).
describe Waha::RichNative::PollVote do
  let(:engine) { 'https://waha.example' }
  let(:account) { create(:account) }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_api, account: account, webhook_url: "#{engine}/webhooks/chatwoot/abc",
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1', 'account_token_owner_user_id' => connector.id })
  end
  let(:inbox) { channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:poll_rich) { { type: 'poll', options: [{ id: 'sim', title: 'Sim' }, { id: 'nao', title: 'Não' }], multiple: true } }
  let(:capabilities) { %w[options location contact poll] }

  around { |example| with_modified_env(WAHA_RICH_NATIVE_ENGINES: "#{engine}/") { example.run } }

  before { allow(Waha::EngineCapabilities).to receive(:types) { |url| url == "#{engine}/" ? capabilities : [] } }

  def poll_message
    create(:message, message_type: :outgoing, content: 'Vem amanhã?', conversation: conversation, inbox: inbox, account: account,
                     content_attributes: { rich_message: poll_rich })
  end

  def inbox_payload(message)
    payloads = []
    allow(WebhookJob).to receive(:perform_later) { |_url, payload, kind, **| payloads << payload if kind == :api_inbox_webhook }
    WebhookListener.instance.message_created(Events::Base.new('message_created', Time.zone.now, message: message))
    payloads.sole
  end

  after { Current.reset }

  # O voto chega pela API com o token do conector.
  def vote(poll, options, extra = {})
    Current.user = connector
    create(:message, message_type: :incoming, content: options.join(', '), conversation: conversation, inbox: inbox,
                     account: account, sender: conversation.contact,
                     content_attributes: { in_reply_to: poll.id,
                                           waha_poll_vote: { poll_message_id: poll.id, options: options, vote_id: 'v1', timestamp: 1 } }
                       .merge(extra)).reload
  ensure
    Current.user = nil
  end

  it 'sends the poll natively with the flag and an engine that returns the vote' do
    account.enable_features!(Waha::RichNative::FLAG)
    message = poll_message

    payload = inbox_payload(message)

    expect(message.reload.content_attributes['rich_message_sent_as']).to eq('native')
    # A versão em texto (para o conector sem enquete) leva o aviso de mais de uma resposta (Poll::MULTIPLE_HINT).
    expect(payload[:content]).to eq("Vem amanhã?\n\n1. Sim\n2. Não\nPode escolher mais de uma")
    expect(payload[:content_attributes]['waha_native']).to eq(
      'kind' => 'sendPoll', 'payload' => { 'poll' => { 'name' => 'Vem amanhã?', 'options' => %w[Sim Não], 'multipleAnswers' => true } }
    )
  end

  it 'is refused at creation without the flag (unknown type, as in main)' do
    message = Message.new(account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Vem?',
                          content_attributes: { 'rich_message' => poll_rich.deep_stringify_keys })
    expect(RichMessages.error_for(message)).to eq(RichMessages::UNKNOWN_TYPE)
  end

  describe 'the vote (waha_poll_vote)' do
    before { account.enable_features!(Waha::RichNative::FLAG) }

    # A mensagem do voto é o turno do cliente para a IA (recebida, com o texto claro) e fica escondida na tela.
    it 'aggregates the vote on the poll by the offered titles and makes the vote a hidden customer turn' do
      poll = poll_message
      inbox_payload(poll)

      answer = vote(poll.reload, %w[Não Sim])

      expect(answer).to be_incoming
      expect(answer.content).to eq('Voted: Não, Sim')
      expect(Waha::RichNative::AiChoiceText.for(answer)).to eq("Voted in the poll 'Vem amanhã?': Não, Sim")
      expect(answer.content_attributes).to include('c2y_hidden' => true, 'poll_vote_applied_to' => poll.id)
      expect(answer.content_attributes.keys & %w[selected_option selected_options waha_poll_vote]).to eq([])
      vote_entry = poll.reload.content_attributes['poll_votes'].sole
      expect(vote_entry).to include('sender_type' => 'Contact', 'sender_id' => conversation.contact_id, 'options' => %w[Não Sim])
      expect(vote_entry['at']).to be_present
    end

    # Resposta dupla da IA: o mesmo voto refeito (retry do conector, mesma hora ou sem hora) não é turno novo. Caminho
    # real: conector -> recebimento -> record_vote! -> listener do agente.
    it 'makes only one customer turn when the same vote arrives twice, and a new turn when the choice changes' do
      allow(Autonomia::Agents::Config).to receive(:enabled?).and_return(true)
      poll = poll_message
      inbox_payload(poll)
      listener = Autonomia::Agents::Operate::MessageListener.instance
      ouvir = ->(message) { listener.message_created(Events::Base.new('message.created', Time.zone.now, message: message)) }

      primeiro = vote(poll.reload, ['Sim'])
      repetido = vote(poll.reload, ['Sim'])
      trocado = vote(poll.reload, ['Não'])

      expect([primeiro, repetido, trocado].map(&:message_type)).to eq(%w[incoming activity incoming])
      expect { [primeiro, repetido, trocado].each { |message| ouvir.call(message) } }
        .to have_enqueued_job(Autonomia::Agents::Operate::ReplyJob).exactly(2).times
      expect(primeiro.content_attributes['c2y_ai_turn']).to include('kind' => 'poll_vote', 'target_id' => poll.id, 'choice' => ['Sim'])
    end

    it 'makes a new turn for the same choice only when the engine time is strictly newer' do
      poll = poll_message
      inbox_payload(poll)
      hora = Time.zone.now.to_i - 60

      vote(poll.reload, ['Sim'], waha_poll_vote: { poll_message_id: poll.id, options: ['Sim'], vote_id: 'v1', timestamp: hora })
      igual = vote(poll.reload, ['Sim'], waha_poll_vote: { poll_message_id: poll.id, options: ['Sim'], vote_id: 'v1', timestamp: hora })
      mais_novo = vote(poll.reload, ['Sim'], waha_poll_vote: { poll_message_id: poll.id, options: ['Sim'], vote_id: 'v2', timestamp: hora + 30 })

      expect(igual).to be_activity
      expect(mais_novo).to be_incoming
    end

    it 'keeps one entry per voter: a new vote replaces the previous one and a removed vote keeps the voter' do
      poll = poll_message
      inbox_payload(poll)

      vote(poll.reload, ['Sim'])
      vote(poll.reload, ['Não'])
      expect(poll.reload.content_attributes['poll_votes'].sole['options']).to eq(['Não'])

      expect(vote(poll.reload, [])).to be_activity
      expect(poll.reload.content_attributes['poll_votes'].sole['options']).to eq([])
    end

    it 'stays plain text when the poll is not ours, not native, or the title was not offered' do
      text_poll = poll_message # sem o pedido nativo: fica 'text'
      text_poll.update!(content_attributes: text_poll.content_attributes.merge('rich_message_sent_as' => 'text'))
      native = poll_message
      inbox_payload(native)

      [vote(text_poll, ['Sim']), vote(native.reload, ['Talvez'])].each do |answer|
        expect(answer).to be_incoming
        expect(answer.content_attributes.keys & %w[selected_option selected_options waha_poll_vote c2y_hidden]).to eq([])
      end
      expect(native.reload.content_attributes).not_to have_key('poll_votes')
    end

    it 'hides the vote of a poll sent before the flag was turned off (main never gets a vote)' do
      account.disable_features!(Waha::RichNative::FLAG)
      poll = poll_message
      answer = vote(poll, ['Sim'])

      expect(answer).to be_activity
      expect(answer.content_attributes).to include('c2y_hidden' => true)
      expect(answer.content_attributes.keys & %w[selected_option waha_poll_vote]).to eq([])
      expect(poll.reload.content_attributes).not_to have_key('poll_votes')
    end
  end

  describe Waha::EngineCapabilities do
    let(:cache) { ActiveSupport::Cache::MemoryStore.new }

    before do
      allow(described_class).to receive(:types).and_call_original
      allow(Rails).to receive(:cache).and_return(cache)
    end

    def version(autonomia)
      stub_request(:get, "#{engine}/api/server/version")
        .to_return(status: 200, headers: { 'Content-Type' => 'application/json' }, body: { autonomia: autonomia }.to_json)
    end

    it 'counts poll only with poll_vote and reads the actions' do
      version({ patch: 'c2y-rich-2', rich_native: %w[options location contact poll], list_reply: true, poll_vote: true,
                reactions: true, edit: true })
      described_class.refresh!("#{engine}/")
      expect(described_class.types("#{engine}/")).to eq(%w[options location contact poll])
      expect(described_class.actions("#{engine}/")).to eq(%w[react edit])

      version({ patch: 'c2y-rich-1', rich_native: %w[options poll], list_reply: true })
      described_class.refresh!("#{engine}/")
      expect(described_class.types("#{engine}/")).to eq(%w[options])
      expect(described_class.actions("#{engine}/")).to eq([])
    end
  end
end

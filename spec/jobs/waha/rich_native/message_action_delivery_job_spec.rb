require 'rails_helper'

# chat#1709 (rodada de correção, item 12): a reação e a edição pelo painel vão ao conector por um job que sabe se o
# evento chegou. Falha: nova tentativa; esgotada, uma nota privada na conversa, sem desfazer a mudança.
describe Waha::RichNative::MessageActionDeliveryJob do
  include ActiveJob::TestHelper

  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc', secret: 'segredo-de-teste',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:account) { channel.account }
  let(:conversation) { create(:conversation, inbox: channel.inbox, account: account) }
  let(:message) do
    create(:message, message_type: :incoming, content: 'oi', conversation: conversation, inbox: channel.inbox, account: account)
  end
  let(:payload) { { 'event' => 'c2y_message_reaction', 'id' => message.id, 'c2y_reaction' => { 'emoji' => '👍' } } }

  before { account.update!(locale: 'pt_BR') }

  it 'posts the signed event to the inbox webhook' do
    allow(SafeFetch).to receive(:fetch)

    described_class.perform_now(message.id, payload, 'D1')

    expect(SafeFetch).to have_received(:fetch).once.with(
      channel.webhook_url,
      hash_including(method: :post, body: payload.to_json,
                     headers: hash_including('X-Chatwoot-Delivery' => 'D1', 'X-Chatwoot-Signature' => start_with('sha256=')))
    )
    expect(conversation.messages.where(private: true)).to be_empty
  end

  it 'retries a failure and, when the attempts run out, leaves a private note and keeps the reaction' do
    message.update_column(:content_attributes, { 'reactions' => [{ 'emoji' => '👍', 'sender_type' => 'User' }] }) # rubocop:disable Rails/SkipsModelValidations
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('500 Internal Server Error', status: 500))

    perform_enqueued_jobs { described_class.perform_later(message.id, payload, 'D1') }

    # As tentativas do evento (a nota nova também vai ao webhook da caixa, como toda mensagem, e o conector a ignora).
    expect(SafeFetch).to have_received(:fetch).with(channel.webhook_url, hash_including(body: payload.to_json))
                                              .exactly(described_class::ATTEMPTS).times
    note = conversation.messages.where(private: true).sole
    expect(note.content).to eq('A reação não chegou ao WhatsApp do cliente. Ela ficou registrada só aqui no chat2you.')
    expect(note).to be_outgoing
    expect(message.reload.content_attributes['reactions']).to be_present
  end

  it 'says the edit did not arrive, for the edit event' do
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::FetchError, 'timeout')

    perform_enqueued_jobs { described_class.perform_later(message.id, payload.merge('event' => 'c2y_message_edit'), 'D2') }

    expect(conversation.messages.where(private: true).sole.content)
      .to eq('A edição não chegou ao WhatsApp do cliente. O cliente continua vendo o texto anterior.')
  end

  # Revisão da rodada de correção, itens 4 e 5: erro que não passa com o tempo vai direto ao aviso; caixa sem webhook
  # também avisa, em vez de sair calada.
  { 'endereço recusado' => SafeFetch::UnsafeUrlError.new('privado'), 'endereço inválido' => SafeFetch::InvalidUrlError.new('x'),
    'recusa 4xx' => SafeFetch::HttpError.new('401 Unauthorized', status: 401) }.each do |caso, erro|
    it "does not retry a permanent failure (#{caso}) and leaves the note at once" do
      allow(SafeFetch).to receive(:fetch).and_raise(erro)

      perform_enqueued_jobs { described_class.perform_later(message.id, payload, 'D3') }

      expect(SafeFetch).to have_received(:fetch).with(channel.webhook_url, hash_including(body: payload.to_json)).once
      expect(conversation.messages.where(private: true).count).to eq(1)
    end
  end

  it 'leaves the note when the inbox has no webhook address' do
    allow(SafeFetch).to receive(:fetch)
    channel.update!(webhook_url: '')

    described_class.perform_now(message.id, payload, 'D4')

    expect(SafeFetch).not_to have_received(:fetch).with(anything, hash_including(body: payload.to_json))
    expect(conversation.messages.where(private: true).sole.content).to start_with('A reação não chegou')
  end
end

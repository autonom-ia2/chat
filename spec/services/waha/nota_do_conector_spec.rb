require 'rails_helper'

# #1941, item 2: a nota técnica do conector WAHA ("Não foi possível receber uma mensagem") vira um aviso curto e humano.
describe Waha::NotaDoConector do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:nota) do
    <<~NOTA
      ⚠️ **Não foi possível receber uma mensagem do WhatsApp**
      ❌ Não há mais tentativas restantes. Por favor, tente novamente mais tarde.
      Tentativa: 3 / 3
      Detalhes: [whatsapp | message.any => 583011](https://wa-hub.example/jobs/queue/chatwoot.waha%20%7C%20message.any/583011)
      ```

      API Error: Request failed with status code 404Data: <unparsable>
      ```
    NOTA
  end
  let(:aviso) { '⚠️ Uma mensagem do WhatsApp não chegou aqui. Confira no celular da caixa.' }

  before do
    account.update!(locale: 'pt_BR')
    channel.update!(additional_attributes: channel.additional_attributes.merge('account_token_owner_user_id' => connector.id))
  end

  after { Current.reset }

  def criar(content:, user: connector, target_inbox: inbox, target: conversation, **opcoes)
    Current.user = user
    create(:message, message_type: opcoes.fetch(:message_type, :outgoing), private: opcoes.fetch(:private, true),
                     inbox: target_inbox, account: account, conversation: target, sender: user, content: content,
                     content_attributes: opcoes.fetch(:attributes, {})).reload
  ensure
    Current.user = nil
  end

  it 'troca a nota do conector por um aviso humano, fora do webhook' do
    message = criar(content: nota, attributes: { external_error: '404 Not Found' })

    expect(message).to be_activity
    expect(message.private).to be(false)
    expect(message.content).to eq(aviso)
    expect(message.processed_message_content).to eq(aviso)
    expect(message.content_attributes).not_to have_key('external_error')
    expect(message.webhook_sendable?).to be(false)
  end

  it 'guarda no log só o job do motor, sem o link' do
    allow(Rails.logger).to receive(:warn)

    criar(content: nota)

    expect(Rails.logger).to have_received(:warn).with(include('job=message.any => 583011', "conversation=#{conversation.id}"))
    expect(Rails.logger).not_to have_received(:warn).with(include('wa-hub'))
  end

  it 'deixa a nota como veio quando o aviso não pode ser montado' do
    allow(I18n).to receive(:t).and_call_original
    allow(I18n).to receive(:t).with(described_class::TEXT_KEY, any_args).and_raise(I18n::ArgumentError)

    message = criar(content: nota)

    expect(message).to be_outgoing
    expect(message.private).to be(true)
    expect(message.content).to eq(nota)
  end

  it 'não mexe na nota de quem não é o conector' do
    message = criar(content: nota, user: agent)

    expect(message).to be_outgoing
    expect(message.private).to be(true)
    expect(message.content).to eq(nota)
  end

  it 'não mexe em outra nota do conector' do
    texto = "⚠️ **chatwoot.scheduled | message.cleanup: Falha ao executar tarefa agendada**\nTentativa: 3 / 3"

    expect(criar(content: texto).content).to eq(texto)
  end

  it 'não mexe em mensagem que não é nota' do
    message = criar(content: nota, private: false)

    expect(message).to be_outgoing
    expect(message.content).to eq(nota)
  end

  it 'não mexe em caixa que não é WAHA comum' do
    outra = create(:channel_api, account: account).inbox
    alvo = create(:conversation, inbox: outra, account: account)

    message = criar(content: nota, target_inbox: outra, target: alvo)

    expect(message).to be_outgoing
    expect(message.content).to eq(nota)
  end
end

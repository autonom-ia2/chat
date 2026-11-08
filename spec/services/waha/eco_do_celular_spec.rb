require 'rails_helper'

# #1941, item 3: o eco da resposta pelo celular na caixa WAHA comum chega sem o prefixo do conector e com o autor
# congelado (quem estava atribuído quando chegou).
describe Waha::EcoDoCelular do
  let(:channel) do
    create(:channel_api, webhook_url: 'https://waha.example/webhooks/chatwoot/abc',
                         additional_attributes: { 'provider' => 'waha', 'session' => 's1' })
  end
  let(:inbox) { channel.inbox }
  let(:account) { channel.account }
  let(:connector) { create(:user, account: account, role: :administrator) }
  let(:joao) { create(:user, account: account, role: :agent) }
  let(:jose) { create(:user, account: account, role: :agent) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, assignee: joao) }
  let(:prefixo) { "*📱 Enviado do WhatsApp*\n\n" }

  before do
    channel.update!(additional_attributes: channel.additional_attributes.merge('account_token_owner_user_id' => connector.id))
  end

  after { Current.reset }

  def criar(content:, attributes: { external_echo: true }, message_type: :outgoing, user: connector, target: conversation)
    Current.user = user
    create(:message, message_type: message_type, inbox: inbox, account: account, conversation: target,
                     content: content, sender: message_type == :incoming ? target.contact : user,
                     content_attributes: attributes).reload
  ensure
    Current.user = nil
  end

  it 'tira o prefixo e grava quem estava atribuído' do
    message = criar(content: "#{prefixo}Olá ☺️\nVoltamos dia 20.")

    expect(message.content).to eq("Olá ☺️\nVoltamos dia 20.")
    expect(message.processed_message_content).to eq("Olá ☺️\nVoltamos dia 20.")
    expect(message.content_attributes['c2y_phone_author_id']).to eq(joao.id)
    expect(message.content_attributes['external_echo']).to be(true)
    expect(message.sender).to eq(connector)
  end

  it 'grava null quando a conversa está sem atribuição' do
    conversation.update!(assignee: nil)

    message = criar(content: "#{prefixo}Oi")

    expect(message.content).to eq('Oi')
    expect(message.content_attributes).to have_key('c2y_phone_author_id')
    expect(message.content_attributes['c2y_phone_author_id']).to be_nil
  end

  it 'mantém o autor antigo depois de reatribuir a conversa' do
    antiga = criar(content: "#{prefixo}Primeira")
    conversation.update!(assignee: jose)
    nova = criar(content: "#{prefixo}Segunda")

    expect(antiga.reload.content_attributes['c2y_phone_author_id']).to eq(joao.id)
    expect(nova.content_attributes['c2y_phone_author_id']).to eq(jose.id)
  end

  it 'deixa o conteúdo vazio quando o eco só tinha o prefixo (mídia sem legenda)' do
    message = criar(content: "*📱 Enviado do WhatsApp*\n")

    expect(message.content).to be_nil
    expect(message.content_attributes['c2y_phone_author_id']).to eq(joao.id)
  end

  it 'tira quebra de linha do Windows depois do prefixo' do
    expect(criar(content: "*📱 Enviado do WhatsApp*\r\n\r\nOi").content).to eq('Oi')
  end

  it 'grava o autor e não mexe no texto que não começa pelo prefixo' do
    message = criar(content: 'Oi *📱 Enviado do WhatsApp*')

    expect(message.content).to eq('Oi *📱 Enviado do WhatsApp*')
    expect(message.content_attributes['c2y_phone_author_id']).to eq(joao.id)
  end

  it 'não mexe na mensagem enviada pelo painel (sem external_echo)' do
    message = criar(content: "#{prefixo}Oi", attributes: {}, user: joao)

    expect(message.content).to eq("#{prefixo}Oi")
    expect(message.content_attributes).not_to have_key('c2y_phone_author_id')
  end

  it 'não mexe na mensagem recebida' do
    message = criar(content: "#{prefixo}Oi", message_type: :incoming)

    expect(message.content).to eq("#{prefixo}Oi")
    expect(message.content_attributes).not_to have_key('c2y_phone_author_id')
  end

  it 'não aceita o eco de quem não é o conector' do
    message = criar(content: "#{prefixo}Oi", user: joao)

    expect(message.content).to eq("#{prefixo}Oi")
    expect(message.content_attributes).not_to have_key('c2y_phone_author_id')
  end

  it 'não mexe em caixa que não é WAHA comum' do
    outra = create(:channel_api, account: account).inbox
    alvo = create(:conversation, inbox: outra, account: account, assignee: joao)
    Current.user = connector
    message = create(:message, message_type: :outgoing, inbox: outra, account: account, conversation: alvo, sender: connector,
                               content: "#{prefixo}Oi", content_attributes: { external_echo: true }).reload

    expect(message.content).to eq("#{prefixo}Oi")
    expect(message.content_attributes).not_to have_key('c2y_phone_author_id')
  end
end

require 'rails_helper'

# #1941 — a falha do webhook da caixa API só marca "Falha ao enviar" no que o chat2you manda ao cliente por ele.
describe Webhooks::FalhaSoNoQueSai do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }

  def falhar_webhook_de(message, event: 'message_created')
    allow(SafeFetch).to receive(:fetch).and_raise(SafeFetch::HttpError.new('404 Not Found'))
    Webhooks::Trigger.execute('https://conector.example/webhook', { event: event, id: message.id }, :api_inbox_webhook)
    message.reload
  end

  def mensagem(**attrs)
    create(:message, account: account, inbox: inbox, conversation: conversation, **attrs)
  end

  it 'marca a resposta do atendente que não saiu' do
    resposta = falhar_webhook_de(mensagem(message_type: :outgoing))

    expect(resposta.status).to eq('failed')
    expect(resposta.content_attributes['external_error']).to eq('404 Not Found')
  end

  it 'marca o modelo que não saiu' do
    expect(falhar_webhook_de(mensagem(message_type: :template)).status).to eq('failed')
  end

  it 'marca a edição que não chegou de uma resposta ainda não entregue' do
    expect(falhar_webhook_de(mensagem(message_type: :outgoing), event: 'message_updated').status).to eq('failed')
  end

  it 'não marca a resposta que já foi entregue ou lida quando um message_updated depois falha' do
    entregue = falhar_webhook_de(mensagem(message_type: :outgoing, status: :delivered), event: 'message_updated')
    lida = falhar_webhook_de(mensagem(message_type: :outgoing, status: :read), event: 'message_updated')

    expect([entregue.status, lida.status]).to eq(%w[delivered read])
    expect(lida.content_attributes).not_to have_key('external_error')
  end

  it 'não marca a mensagem que o cliente mandou' do
    recebida = falhar_webhook_de(mensagem(message_type: :incoming))

    expect(recebida.status).to eq('sent')
    expect(recebida.content_attributes).not_to have_key('external_error')
  end

  it 'não marca o eco do que saiu pelo celular' do
    eco = falhar_webhook_de(mensagem(message_type: :outgoing, content_attributes: { external_echo: true }))

    expect(eco.status).to eq('sent')
    expect(eco.content_attributes).not_to have_key('external_error')
  end

  it 'não marca a nota interna' do
    nota = falhar_webhook_de(mensagem(message_type: :outgoing, private: true))

    expect(nota.status).to eq('sent')
  end
end

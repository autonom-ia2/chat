require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::Rede do
  describe 'Página do Facebook' do
    let(:channel) { instance_double(Channel::FacebookPage, page_id: '555', page_access_token: 'token-da-pagina') }
    let(:inbox) { instance_double(Inbox, channel: channel) }
    let(:rede) { described_class.new(described_class::Pagina.new(channel)) }
    let(:graph) { 'https://graph.facebook.com/v22.0' }

    before { allow(channel).to receive(:is_a?) { |klass| klass == Channel::FacebookPage } }

    it 'manda o privado pelo Messenger em resposta ao comentário, com o token da Página no cabeçalho' do
      pedido = stub_request(:post, "#{graph}/555/messages")
               .with(headers: { 'Authorization' => 'Bearer token-da-pagina' },
                     body: hash_including('recipient' => { 'comment_id' => 'c-1' }, 'message' => { 'text' => 'Oi!' },
                                          'messaging_type' => 'RESPONSE'))
               .to_return(status: 200, body: { recipient_id: 'psid-1', message_id: 'mid-1' }.to_json)

      envio = rede.private_reply('c-1', 'Oi!', button: nil)

      expect(pedido).to have_been_made
      expect(envio).to have_attributes(ok: true, recipient_id: 'psid-1', message_id: 'mid-1')
    end

    it 'com botão, manda o modelo de botão que abre o WhatsApp' do
      pedido = stub_request(:post, "#{graph}/555/messages").with(body: hash_including(
        'message' => { 'attachment' => { 'type' => 'template', 'payload' => {
          'template_type' => 'button', 'text' => 'Oi!',
          'buttons' => [{ 'type' => 'web_url', 'url' => 'https://wa.me/55119', 'title' => 'Chamar no WhatsApp' }]
        } } }
      )).to_return(status: 200, body: { recipient_id: 'psid-1', message_id: 'mid-1' }.to_json)

      rede.private_reply('c-1', 'Oi!', button: { 'title' => 'Chamar no WhatsApp', 'url' => 'https://wa.me/55119' })

      expect(pedido).to have_been_made
    end

    it 'recusa da Meta vira envio sem sucesso, com o erro limpo' do
      stub_request(:post, "#{graph}/555/messages")
        .to_return(status: 400, body: { error: { code: 10, message: 'Fora da janela' } }.to_json)

      expect(rede.private_reply('c-1', 'Oi!', button: nil)).to have_attributes(ok: false, erro: '10 - Fora da janela')
    end

    it 'responde no comentário e esconde o comentário' do
      resposta = stub_request(:post, "#{graph}/c-1/comments")
                 .with(body: hash_including('message' => 'Te chamei no Messenger'))
                 .to_return(status: 200, body: { id: 'c-2' }.to_json)
      esconder = stub_request(:post, "#{graph}/c-1")
                 .with(body: hash_including('is_hidden' => true))
                 .to_return(status: 200, body: { success: true }.to_json)

      expect(rede.reply('c-1', 'Te chamei no Messenger').ok).to be(true)
      expect(rede.hide('c-1').ok).to be(true)
      expect([resposta, esconder]).to all(have_been_made)
    end

    it 'falha de rede não derruba o job' do
      stub_request(:post, "#{graph}/c-1").to_raise(Net::OpenTimeout)

      expect(rede.hide('c-1').ok).to be(false)
    end
  end
end

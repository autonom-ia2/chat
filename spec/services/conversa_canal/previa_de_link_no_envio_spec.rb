require 'rails_helper'

# #1702 — texto do atendente com endereço sai com `preview_url: true` na Cloud API (a prévia no celular do cliente).
describe ConversaCanal::PreviaDeLinkNoEnvio do
  subject(:service) { Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: canal) }

  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:account) { canal.account }
  let(:conversa) { create(:conversation, account: account, inbox: canal.inbox) }
  let(:url_da_meta) { "https://graph.facebook.com/v13.0/#{canal.provider_config['phone_number_id']}/messages" }

  before do
    account.enable_features!('conversa_cara_do_canal')
    stub_request(:post, url_da_meta)
      .to_return(status: 200, body: { messages: [{ id: 'wamid.X' }] }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def enviar(texto)
    mensagem = create(:message, account: account, inbox: canal.inbox, conversation: conversa, message_type: :outgoing, content: texto)
    service.send_message('+5511999999999', mensagem)
  end

  def texto_enviado
    corpo = nil
    expect(a_request(:post, url_da_meta).with { |pedido| corpo = JSON.parse(pedido.body) }).to have_been_made.once
    corpo['text']
  end

  it 'liga a prévia quando o texto tem endereço' do
    expect(enviar('Segue o link: https://exemplo.com.br/cotacao.')).to eq('wamid.X')

    expect(texto_enviado).to eq('body' => 'Segue o link: https://exemplo.com.br/cotacao.', 'preview_url' => true)
  end

  it 'não liga sem endereço completo (o WhatsApp só lê http:// e https://)' do
    enviar('Acesse exemplo.com.br')

    expect(texto_enviado).not_to have_key('preview_url')
  end

  it 'não liga com a chave desligada' do
    account.disable_features!('conversa_cara_do_canal')

    enviar('https://exemplo.com.br')

    expect(texto_enviado).not_to have_key('preview_url')
  end
end

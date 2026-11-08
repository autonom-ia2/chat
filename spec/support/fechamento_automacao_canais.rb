# As portas de cada canal no teste de fechamento (#2414 F9.7, #2701; F9 §3.2): a mensagem do cliente entra pelo webhook
# real do canal, assinado como a Meta assina, e o que sai para no receptor, na camada HTTP.
#
# - WhatsApp oficial e Híbrido: a mensagem do cliente chega pelo webhook da Cloud (o motor do Híbrido, a WAHA, só avisa
#   status e recibo; ele só manda, e só com a janela de 24 h fechada). A resposta sai pela Graph (`receptor_whatsapp_cloud`)
#   ou, fora da janela, pela WAHA (`receptor_waha`).
# - Instagram: o webhook do Instagram; a resposta sai pela API do Instagram (`receptor_instagram`).
module FechamentoAutomacao::Canais
  SEGREDO_DA_META = 'segredo-do-fechamento'.freeze
  WAHA = 'https://waha.fechamento.test'.freeze
  INSTAGRAM = 'graph.instagram.com'.freeze

  # A Meta assina o corpo com o segredo do app; o controller confere antes de enfileirar o job do canal.
  def webhook_da_meta(caminho, corpo, segredo_env)
    texto = corpo.to_json
    assinatura = "sha256=#{OpenSSL::HMAC.hexdigest('SHA256', SEGREDO_DA_META, texto)}"
    InstallationConfig.where(name: segredo_env.to_s).delete_all
    GlobalConfig.clear_cache
    with_modified_env(segredo_env => SEGREDO_DA_META) do
      post caminho, params: texto, headers: { 'CONTENT_TYPE' => 'application/json', 'X-Hub-Signature-256' => assinatura }
    end
    expect(response).to have_http_status(:ok), -> { "o webhook recusou: #{response.status} #{response.body}" }
  end

  # O cliente escreve no WhatsApp (oficial ou Híbrido): o payload da Cloud, como ela manda.
  def cliente_escreve_pela_cloud(canal, remetente:, nome:, texto:)
    valor = {
      messaging_product: 'whatsapp',
      metadata: { display_phone_number: canal.phone_number.delete('+'), phone_number_id: canal.provider_config['phone_number_id'] },
      contacts: [{ profile: { name: nome }, wa_id: remetente }],
      messages: [{ from: remetente, id: "wamid.cliente#{SecureRandom.hex(6)}", timestamp: Time.current.to_i.to_s, type: 'text',
                   text: { body: texto } }]
    }
    corpo = { object: 'whatsapp_business_account', entry: [{ id: 'waba-fechamento', changes: [{ field: 'messages', value: valor }] }] }
    webhook_da_meta("/webhooks/whatsapp/#{canal.phone_number}", corpo, :WHATSAPP_APP_SECRET)
    rodar_jobs
  end

  # O cliente escreve no Direct do Instagram. O perfil dele (nome) vem da API do Instagram, na primeira mensagem.
  def cliente_escreve_pelo_instagram(canal, remetente:, nome:, texto:)
    stub_request(:get, ->(uri) { uri.host == INSTAGRAM && uri.path == "/v22.0/#{remetente}" }).to_return(
      status: 200, body: { name: nome, username: nome.downcase, id: remetente }.to_json, headers: { 'Content-Type' => 'application/json' }
    )
    evento = { sender: { id: remetente }, recipient: { id: canal.instagram_id }, timestamp: (Time.current.to_f * 1000).to_i,
               message: { mid: "mid.cliente#{SecureRandom.hex(6)}", text: texto } }
    corpo = { object: 'instagram', entry: [{ id: canal.instagram_id, time: Time.current.to_i, messaging: [evento] }] }
    webhook_da_meta('/webhooks/instagram', corpo, :INSTAGRAM_APP_SECRET)
    rodar_jobs
  end

  # O Instagram: o SendReplyJob chama a API do Instagram de verdade. O "digitando" (sender_action) vai para o mesmo
  # endereço e também fica gravado; `respostas_do_instagram` são só as mensagens. O serviço manda o corpo como formulário
  # (HTTParty com hash), que a Graph aceita: o receptor lê do mesmo jeito.
  def receptor_instagram
    stub_request(:post, ->(uri) { uri.host == INSTAGRAM && uri.path.end_with?('/messages') }).to_return do |pedido|
      corpo = Rack::Utils.parse_nested_query(pedido.body)
      receptor << FechamentoAutomacao::Chamada.new(metodo: 'POST', host: pedido.uri.host, caminho: pedido.uri.path, corpo: corpo)
      { status: 200, body: { recipient_id: 'cliente', message_id: "mid.F9#{receptor.size}" }.to_json,
        headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def respostas_do_instagram = chamadas_para(INSTAGRAM).select { |chamada| chamada.corpo.key?('message') }

  # A WAHA do Híbrido (a caixa usa o host do ambiente, WAHA_API_URL). Grava qualquer pedido; o exemplo com a janela aberta
  # confere que nada passou por aqui.
  def receptor_waha
    host = URI(WAHA).host
    stub_request(:any, ->(uri) { uri.host == host }).to_return do |pedido|
      corpo = pedido.body.present? ? JSON.parse(pedido.body) : {}
      receptor << FechamentoAutomacao::Chamada.new(metodo: pedido.method.to_s.upcase, host: host, caminho: pedido.uri.path, corpo: corpo)
      { status: 200, body: { id: "waha.F9#{receptor.size}" }.to_json, headers: { 'Content-Type' => 'application/json' } }
    end
  end

  def chamadas_para_a_waha = chamadas_para(URI(WAHA).host)
end

RSpec.configure do |config|
  config.include FechamentoAutomacao::Canais, :fechamento_automacao
end

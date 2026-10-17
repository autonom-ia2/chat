# A pergunta sobre um produto do catálogo (#1702): na página do produto o cliente toca em "Mensagem" e o app manda o
# texto com a citação do produto. A Cloud API entrega o produto em `context.referred_product`
# ({ catalog_id, product_retailer_id }); o Chatwoot descartava e a conversa perdia de qual produto se falava.
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/text.md
# (exemplo "Product inquiry", lido em 17/10/2026)
#
# Grava em `content_attributes.referred_product` o código e, quando o catálogo da caixa responde, nome, preço e foto,
# lidos como na foto do envio (`Enviado::Produtos`: primeiro o guardado, depois a Meta com prazo curto, uma tentativa).
# Quem chama lê ANTES da transação que cria a mensagem: a consulta à Meta nunca segura o banco.
module ConversaCanal::ProdutoCitado
  ID_MAX = Whatsapp::Templates::Enviado::Produtos::ID_MAX
  Produtos = Whatsapp::Templates::Enviado::Produtos

  module_function

  # { 'catalog_id', 'product_retailer_id', 'nome'?, 'preco'?, 'foto_url'? }, ou nil quando a mensagem não cita produto.
  def de(contexto, inbox)
    citado = contexto.respond_to?(:key?) ? contexto[:referred_product] : nil
    return unless citado.respond_to?(:key?)

    codigo = citado[:product_retailer_id].to_s.strip.first(ID_MAX).presence
    return unless codigo

    { 'catalog_id' => citado[:catalog_id].to_s.strip.first(ID_MAX).presence, 'product_retailer_id' => codigo }
      .merge(do_catalogo(inbox, codigo)).compact
  end

  # Nome, preço e foto do catálogo da caixa; sem resposta, nada (a tela mostra o código).
  def do_catalogo(inbox, codigo)
    modo = Whatsapp::Templates::MetaClient.supported?(inbox) ? :consultar : :guardado
    Produtos.item(codigo, Produtos.ler(inbox, [codigo], modo, nil)[codigo]).except('retailer_id')
  rescue StandardError => e
    # O recebimento segue só com o código. Só a classe vai ao log.
    Rails.logger.warn("[conversa_canal][produto_citado] catalogo_indisponivel inbox_id=#{inbox&.id} error=#{e.class}")
    {}
  end
end

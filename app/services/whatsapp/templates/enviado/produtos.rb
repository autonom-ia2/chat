# Os produtos na foto do envio (#1717): nome, preço e foto do catálogo da caixa (`CatalogClient`) na hora do envio.
# Se a Meta não responde, cada produto fica só com o retailer_id.
#
# O envio não pode esperar a Meta: a consulta tem prazo curto e uma tentativa só. A campanha não consulta por pessoa:
# o disparo (`DispatchProducts`) já leu os produtos e os deixa guardados aqui (`lembrar`); cada envio lê o guardado.
module Whatsapp::Templates::Enviado::Produtos
  PRAZO = 2
  # Além das 72 horas em que a resposta de uma campanha ainda grava a mensagem na conversa (`record_at_reply`).
  GUARDA = 4.days
  MAX = 30
  ID_MAX = 100
  NOME_MAX = 60
  PRECO_MAX = 30

  module_function

  # { 'produto' => {…} } no topo de produto (SPM); { 'produtos' => [...] } na lista (MPM) e no carrossel de produtos.
  def foto(template, processed, inbox, catalogo)
    tipo = Whatsapp::Templates::ProductParams.kind(template)
    ids = Whatsapp::Templates::ProductParams.retailer_ids(processed).first(MAX)
    return {} if tipo.nil? || ids.empty?

    lidos = ler(inbox, ids, catalogo, processed.dig('products', 'catalog_id'))
    itens = ids.map { |id| item(id, lidos[id]) }
    tipo == 'um' ? { 'produto' => itens.first } : { 'produtos' => itens }
  end

  def item(id, lido)
    foto = { 'retailer_id' => id.first(ID_MAX) }
    return foto unless lido

    foto.merge('nome' => lido['name'].to_s.strip.first(NOME_MAX).presence, 'preco' => lido['price'].to_s.strip.first(PRECO_MAX).presence,
               'foto_url' => Whatsapp::Templates::Enviado::Links.foto(lido['image_url']))
  end

  # { retailer_id => { 'name', 'price', 'image_url' } }: o que a Meta respondeu agora (:consultar) e, no que faltar, o
  # que o disparo deixou guardado.
  def ler(inbox, ids, catalogo, catalog_id)
    guardados = guardados(inbox, ids)
    faltam = ids - guardados.keys
    return guardados if faltam.empty? || catalogo != :consultar

    guardados.merge(consultar(inbox, faltam, catalog_id))
  end

  # Com o catálogo que o envio já leva (`products.catalog_id`, posto pelo disparo), uma consulta só.
  def consultar(inbox, ids, catalog_id)
    cliente = Whatsapp::Templates::CatalogClient.new(inbox: inbox, timeout: PRAZO, insistir: false)
    achados = cliente.find(ids, catalog_id: catalog_id.to_s.presence).values
    lembrar(inbox, achados)
    achados.index_by(&:id).transform_values { |produto| valores(produto) }
  rescue StandardError => e
    # A foto fica só com o retailer_id; o envio segue. Só a classe vai ao log.
    Rails.logger.warn("[whatsapp][templates][enviado] catalogo_indisponivel inbox_id=#{inbox&.id} error=#{e.class}")
    {}
  end

  # Guarda os produtos lidos (pelo disparo da campanha ou por um envio) para os próximos envios da caixa.
  def lembrar(inbox, produtos)
    return if produtos.blank?

    Rails.cache.write_multi(produtos.to_h { |produto| [chave(inbox, produto.id), valores(produto)] }, expires_in: GUARDA)
  end

  def guardados(inbox, ids)
    chaves = ids.index_by { |id| chave(inbox, id) }
    Rails.cache.read_multi(*chaves.keys).transform_keys { |chave| chaves[chave] }
  end

  # O preço que o cliente vê: o de promoção dentro do período dela (#1716), senão o cheio.
  def valores(produto)
    { 'name' => produto.name, 'price' => produto.sale_price.presence || produto.price, 'image_url' => produto.image_url }
  end

  def chave(inbox, id)
    "whatsapp:enviado:produto:inbox:#{inbox.id}:#{id}"
  end
end

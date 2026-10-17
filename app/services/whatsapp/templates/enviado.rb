# A foto do que um envio de modelo levou (#1717, épico #1320), gravada em
# `message.additional_attributes.template_params.enviado` para a conversa mostrar a mensagem como ela saiu, mesmo depois
# de o modelo ser editado, apagado ou trocado. Contrato versão 1, combinado com o Frontend geral em 16/10/2026 (`oferta.texto`
# e `topo` somados em 17/10, opcionais):
#   versao    1
#   oferta    { texto, expira_em? }                            sempre que o modelo tem a oferta: o título dela. A presença de
#                                                              `oferta` NÃO é contagem: ela só existe com `expira_em` (epoch
#                                                              em segundos; modelo com has_expiration e envio com a validade)
#   topo      { tipo: 'text', texto }                          topo de texto, com os valores
#             { tipo: 'image'|'video'|'document', url, nome }  topo de mídia; url só de arquivo nosso, nome só de documento
#   produto   { retailer_id, nome, preco, foto_url }           topo de produto (SPM); não se repete em `topo`
#   produtos  [{ retailer_id, nome, preco, foto_url }]         lista (MPM) e carrossel de produtos; até 30
#   botoes    [{ tipo, texto, url? }]                          url só no botão de link, com a variável resolvida
#   cartoes   [{ midia: { tipo, url }, texto, botoes }]        carrossel de mídia; até 10
# Só os campos do contrato, curtos: nada de descrição, payload de resposta rápida ou telefone. O código do cupom
# (COPY_CODE) NUNCA entra: o botão vai só com o texto. Link só http(s) (`Links`). Mídia de topo e de cartão só do nosso
# armazenamento (`Topo`, `Cartoes`); foto de produto só do catálogo, https e não temporária (`Produtos`).
#
# Lida da estrutura do modelo (`components`, esquema da Meta) e do `processed_params` do envio, os mesmos que o
# `Whatsapp::Templates::SendComponents` usa para montar o pedido à Meta. Quem grava: `Whatsapp::Templates::FotoDoEnvio`.
module Whatsapp::Templates::Enviado
  VERSAO = 1
  # A Meta aceita até 16 caracteres no título da oferta.
  OFERTA_TEXTO_MAX = 16

  module_function

  # catalogo: :consultar pergunta à Meta (prazo curto) os produtos; :guardado lê só o que o disparo já leu.
  # perfil: true só ao reler a campanha (`SentMessageRecorder`): topo de mídia sem link nem referência = o arquivo do perfil.
  def montar(template:, processed:, inbox:, catalogo: :consultar, perfil: false)
    processed = as_hash(processed)
    partes = {
      'oferta' => oferta(template, processed),
      'topo' => Whatsapp::Templates::Enviado::Topo.de(template, processed, inbox, perfil: perfil),
      'botoes' => Whatsapp::Templates::Enviado::Botoes.de(Whatsapp::Templates::SendParams.template_buttons(template),
                                                          processed['buttons']).presence,
      'cartoes' => Whatsapp::Templates::Enviado::Cartoes.de(template, processed, inbox).presence
    }.compact
    { 'versao' => VERSAO }.merge(Whatsapp::Templates::Enviado::Produtos.foto(template, processed, inbox, catalogo)).merge(partes)
  end

  # Sempre que o modelo tem a oferta: o título (`limited_time_offer.text`) e, só quando o modelo conta o tempo
  # (has_expiration) e o envio levou a validade, `expira_em`.
  def oferta(template, processed)
    componente = Whatsapp::Templates::SendParams.component(template, 'LIMITED_TIME_OFFER')
    return unless componente

    oferta = { 'texto' => as_hash(componente['limited_time_offer'])['text'].to_s.strip.first(OFERTA_TEXTO_MAX).presence }
    milissegundos = Integer(as_hash(processed['limited_time_offer'])['expiration_time_ms'].to_s, exception: false)
    return oferta unless Whatsapp::Templates::SendParams.offer_with_expiration?(template)

    milissegundos&.positive? ? oferta.merge('expira_em' => milissegundos / 1000) : oferta
  end

  def as_hash(value)
    value.is_a?(Hash) ? value : {}
  end
end

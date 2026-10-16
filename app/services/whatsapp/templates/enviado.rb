# A foto do que um envio de modelo levou (#1717, épico #1320), gravada em
# `message.additional_attributes.template_params.enviado` para a conversa mostrar a mensagem como ela saiu, mesmo depois
# de o modelo ser editado, apagado ou trocado. Contrato versão 1, combinado com o Frontend geral em 16/10/2026:
#   versao    1
#   oferta    { expira_em }                                    validade da oferta, epoch em segundos
#   produto   { retailer_id, nome, preco, foto_url }           topo de produto (SPM)
#   produtos  [{ retailer_id, nome, preco, foto_url }]         lista (MPM) e carrossel de produtos; até 30
#   botoes    [{ tipo, texto, url? }]                          url só no botão de link, com a variável resolvida
#   cartoes   [{ midia: { tipo, url }, texto, botoes }]        carrossel de mídia; até 10
# Só os campos do contrato, curtos: nada de descrição, payload de resposta rápida ou telefone. O código do cupom
# (COPY_CODE) NUNCA entra: o botão vai só com o texto. Link só http(s) (`Links`). Mídia de cartão só do nosso
# armazenamento (`Cartoes`); foto de produto só do catálogo, https e não temporária (`Produtos`).
#
# Lida da estrutura do modelo (`components`, esquema da Meta) e do `processed_params` do envio, os mesmos que o
# `Whatsapp::Templates::SendComponents` usa para montar o pedido à Meta. Quem grava: `Whatsapp::Templates::FotoDoEnvio`.
module Whatsapp::Templates::Enviado
  VERSAO = 1

  module_function

  # catalogo: :consultar pergunta à Meta (prazo curto) os produtos; :guardado lê só o que o disparo já leu.
  def montar(template:, processed:, inbox:, catalogo: :consultar)
    processed = as_hash(processed)
    partes = {
      'oferta' => oferta(template, processed),
      'botoes' => Whatsapp::Templates::Enviado::Botoes.de(Whatsapp::Templates::SendParams.template_buttons(template),
                                                          processed['buttons']).presence,
      'cartoes' => Whatsapp::Templates::Enviado::Cartoes.de(template, processed, inbox).presence
    }.compact
    { 'versao' => VERSAO }.merge(Whatsapp::Templates::Enviado::Produtos.foto(template, processed, inbox, catalogo)).merge(partes)
  end

  # Só quando o modelo tem a oferta e o envio levou a validade (mesma regra do `SendComponents`).
  def oferta(template, processed)
    return unless Whatsapp::Templates::SendParams.component(template, 'LIMITED_TIME_OFFER')

    milissegundos = Integer(as_hash(processed['limited_time_offer'])['expiration_time_ms'].to_s, exception: false)
    { 'expira_em' => milissegundos / 1000 } if milissegundos&.positive?
  end

  def as_hash(value)
    value.is_a?(Hash) ? value : {}
  end
end

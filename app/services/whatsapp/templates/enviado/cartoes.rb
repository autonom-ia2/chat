# Os cartões do carrossel de mídia na foto do envio (#1717): a mídia, o texto com os valores e os botões de cada um.
#
# A mídia só leva endereço quando o arquivo é NOSSO (ActiveStorage): o arquivo escolhido na campanha, o aprovado guardado
# no perfil do modelo (`card_files`) ou o que o disparo marcou (`media_signed_id`, `CardMedia.for_dispatch`). O endereço
# é o permanente do armazenamento (o mesmo dos anexos da conversa), nunca o link assinado do envio nem um da Meta, que
# expiram. Link digitado por fora vira nil: a tela mostra o ícone do tipo.
# O carrossel de produtos não passa aqui: cada cartão é um produto e vai em `produtos`.
module Whatsapp::Templates::Enviado::Cartoes
  MAX = 10
  TEXTO_MAX = 200
  BOTOES_MAX = 2
  SendParams = Whatsapp::Templates::SendParams

  module_function

  def de(template, processed, inbox)
    return [] if Whatsapp::Templates::ProductParams.kind(template)

    cartoes = SendParams.cards_of(template).first(MAX)
    enviados = Array(SendParams.as_hash(processed['carousel'])['cards'])
    cartoes.each_with_index.map do |cartao, indice|
      enviado = SendParams.as_hash(enviados[indice])
      { 'midia' => midia(cartao, SendParams.as_hash(enviado['header']), inbox, template, indice),
        'texto' => texto(cartao, enviado['body']),
        'botoes' => Whatsapp::Templates::Enviado::Botoes.de(SendParams.template_buttons(cartao).first(BOTOES_MAX), enviado['buttons']) }
    end
  end

  def midia(cartao, topo, inbox, template, indice)
    tipo = Whatsapp::Templates::CardMedia.format_of(cartao)
    tipo && { 'tipo' => tipo, 'url' => url_estavel(arquivo(topo, inbox, template, indice)) }
  end

  # O texto do cartão com os valores enviados; com campo que ficou sem valor, nil (nunca "{{1}}" na tela).
  def texto(cartao, valores)
    modelo = SendParams.component(cartao, 'BODY')&.dig('text').to_s
    valores = SendParams.as_hash(valores).transform_keys(&:to_s).reject { |_chave, valor| valor.to_s.strip.empty? }
    texto = CampaignJourney::TemplatePlaceholders.render(modelo, valores).strip
    texto.first(TEXTO_MAX).presence unless texto.include?(CampaignJourney::TemplatePlaceholders::OPEN)
  end

  # Referências assinadas: a do disparo ou a do arquivo escolhido, só se o arquivo é desta conta; sem nenhuma, o arquivo
  # do perfil do modelo.
  def arquivo(topo, inbox, template, indice)
    assinado = topo['media_signed_id'].presence || topo['media_blob'].presence
    return da_conta(ActiveStorage::Blob.find_signed(assinado.to_s), inbox) if assinado
    return unless topo['media_stored'] == true

    Whatsapp::Templates::HeaderMedia.profile(inbox, template)&.card_file(indice)&.blob
  end

  # Subido pelo upload dos Modelos para esta conta (metadata), ou arquivo de um perfil de modelo desta caixa.
  def da_conta(blob, inbox)
    return if blob.nil?
    return blob if blob.metadata['account_id'].to_s == inbox.account_id.to_s

    perfis = WhatsappTemplateProfile.for_inbox(inbox).select(:id)
    blob if ActiveStorage::Attachment.exists?(blob_id: blob.id, record_type: 'WhatsappTemplateProfile', record_id: perfis)
  end

  def url_estavel(blob)
    blob && Whatsapp::Templates::Enviado::Links.link(Rails.application.routes.url_helpers.rails_blob_url(blob))
  end
end

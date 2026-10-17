# Que tipo de mensagem a Cloud API não entregou (#1702). Ela manda `type: "unsupported"` (erro 131051) e, quando sabe,
# diz o tipo em `unsupported.type`:
# https://developers.facebook.com/documentation/business-messaging/whatsapp/webhooks/reference/messages/unsupported.md
#
# `content_attributes.unsupported_kind` tem valores fechados para a tela: poll, gif, pinned, edit, view_once, unknown.
# - Só grava com o sinal explícito da Meta. Sem `unsupported.type` (ex.: 131060, aparelho companheiro), não grava nada.
# - Tipo que a Meta disse e não está no mapa: `unknown`.
# - `view_once` fica na lista do contrato, mas a lista oficial da Meta não tem valor para visualização única (pesquisa
#   de 16/10, ver ConversaCanal::VisualizacaoUnica); a Cloud nunca produz esse valor aqui.
module ConversaCanal::TipoNaoSuportado
  TIPOS = %w[poll gif pinned edit view_once unknown].freeze
  DA_META = {
    'poll_creation' => 'poll',
    'poll_update' => 'poll',
    'gif' => 'gif',
    'pin' => 'pinned',
    'edit' => 'edit'
  }.freeze

  module_function

  # -> um de TIPOS, ou nil sem sinal da Meta.
  def de(message)
    tipo_da_meta = message.dig(:unsupported, :type).to_s
    return if tipo_da_meta.blank?

    DA_META.fetch(tipo_da_meta) do
      Rails.logger.info("[conversa_canal][unsupported] unmapped type=#{tipo_da_meta.first(40)}")
      'unknown'
    end
  end
end

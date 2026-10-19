# Prepend na classe singleton de Crm::Subjects (chat#1709, rodada de correção, item 16), em arquivo próprio para não
# editar o do Multifunnel: com a flag `whatsapp_rich_native`, a bolha "abra no celular" (`is_unsupported`) e o aviso de
# visualização única (`view_once_unavailable`) não são o que o cliente disse. Não há assunto para identificar neles:
# o IdentifyJob (e a avaliação que ele agenda no card em foco) não roda por causa deles. Sem a flag, como na main.
module Waha::RichNative::SubjectsSkip
  def identificar_depois(message)
    return if message.present? && Waha::RichNative::TurnKinds.kind(message) == :unsupported && Waha::RichNative.enabled?(message.account)

    super
  end
end

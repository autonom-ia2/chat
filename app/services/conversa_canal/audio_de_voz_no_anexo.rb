# Prepend em Attachment (#1702): a marca `meta.is_voice_message` do áudio vai para a tela dentro de `meta`, no mesmo
# formato do WhatsApp Híbrido (Waha::RichNative::AttachmentMeta, #1709). O Chatwoot só leva `meta` no anexo de contato.
# Só com a pele ligada na conta; sem ela, o anexo sai como na main.
module ConversaCanal::AudioDeVozNoAnexo
  def push_event_data
    data = super
    return data unless data && audio? && meta.is_a?(Hash) && meta.key?(ConversaCanal::AudioDeVozRecebido::CHAVE)
    return data unless ConversaCanal::Pele.ligada?(account)

    marca = meta.slice(ConversaCanal::AudioDeVozRecebido::CHAVE)
    data.merge(meta: data[:meta].to_h.merge(marca))
  end
end

# Prepend em Attachment (#1702): a marca de figurinha (`meta.is_sticker`) vai junto do anexo para a tela, a lista
# de conversas e os webhooks. Anexo sem a marca sai como sempre, sem a chave.
module ConversaCanal::FigurinhaNoAnexo
  def push_event_data
    data = super
    return data unless data && meta.is_a?(Hash) && meta[ConversaCanal::FigurinhaRecebida::CHAVE] == true

    data.merge(is_sticker: true)
  end
end

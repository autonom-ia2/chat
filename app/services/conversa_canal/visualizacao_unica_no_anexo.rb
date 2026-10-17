# Prepend em Attachment (#1702): a marca de visualização única (`meta.is_view_once`) vai junto do anexo para a tela, a
# lista de conversas e os webhooks. Anexo sem a marca sai como sempre, sem a chave.
module ConversaCanal::VisualizacaoUnicaNoAnexo
  def push_event_data
    data = super
    return data unless data && ConversaCanal::VisualizacaoUnica.marcado?(self)

    data.merge(is_view_once: true)
  end
end

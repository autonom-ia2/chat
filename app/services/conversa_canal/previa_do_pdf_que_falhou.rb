# Prepend em ActiveStorage::Preview (#1702): quando o Poppler não consegue desenhar a 1ª página (PDF com senha,
# quebrado), a falha fica gravada no blob (`metadata['previa_falhou']`). A miniatura (ConversaCanal::PreviaDoPdfNoAnexo)
# deixa de oferecer a prévia desse PDF, e a tela não pede de novo, a cada exibição, uma prévia que sempre falha.
# Só a falha do próprio desenho (ActiveStorage::PreviewError) marca: erro de rede ou de armazenamento tenta de novo.
module ConversaCanal::PreviaDoPdfQueFalhou
  CHAVE = 'previa_falhou'.freeze

  def self.marcada?(blob)
    blob.metadata[CHAVE] == true
  end

  private

  def process
    super
  rescue ActiveStorage::PreviewError
    # update_columns: sem tocar os anexos nem reenviar metadados ao serviço (callbacks do Blob).
    blob.update_columns(metadata: blob.metadata.merge(CHAVE => true)) # rubocop:disable Rails/SkipsModelValidations
    raise
  end
end

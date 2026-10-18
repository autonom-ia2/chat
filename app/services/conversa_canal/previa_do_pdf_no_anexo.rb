# Prepend em Attachment (#1702): PDF ganha a prévia da 1ª página na miniatura (`thumb_url`), como o app mostra
# no cartão do documento. Só com a pele ligada na conta; sem ela, o PDF sai sem miniatura, como no Chatwoot.
# A prévia é gerada sob demanda pelo Active Storage (Poppler) na primeira vez que a tela pede a imagem; PDF com
# senha ou quebrado falha nesse pedido, a tela cai no cartão sem prévia e a falha fica no blob
# (ConversaCanal::PreviaDoPdfQueFalhou): dali em diante a miniatura não oferece mais a prévia.
module ConversaCanal::PreviaDoPdfNoAnexo
  TAMANHO_DA_PREVIA = [600, nil].freeze

  def thumb_url
    return super if image? || !previa_do_pdf?

    url_for(file.preview(resize_to_limit: TAMANHO_DA_PREVIA))
  rescue ActiveStorage::UnpreviewableError => e
    Rails.logger.warn "Unpreviewable PDF attachment: #{id} (#{file.filename}) - #{e.message}"
    ''
  end

  private

  def previa_do_pdf?
    file.attached? && file.content_type == 'application/pdf' && ConversaCanal::Pele.ligada?(account) && file.previewable? &&
      !ConversaCanal::PreviaDoPdfQueFalhou.marcada?(file.blob)
  end
end

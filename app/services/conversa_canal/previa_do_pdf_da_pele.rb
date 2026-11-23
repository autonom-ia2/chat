# frozen_string_literal: true

# Gerador da prévia de PDF (#1702) restrito às contas com a pele. O Chatwoot deixa os geradores de prévia
# desligados (`config.active_storage.previewers = []`, #11888); ligar o Poppler para o app inteiro deixaria a
# rota pública de prévia do Active Storage desenhar PDF de qualquer conta. Aqui só aceita o PDF anexado a uma
# mensagem de conta com a pele ligada.
class ConversaCanal::PreviaDoPdfDaPele < ActiveStorage::Previewer::PopplerPDFPreviewer
  def self.accept?(blob)
    super && ConversaCanal::Pele.ligada?(conta_do(blob))
  end

  # Lista que já carregou os anexos do blob (a ficha da pessoa, #3113) acha em memória, sem uma consulta por PDF.
  def self.conta_do(blob)
    anexos = blob.attachments
    dono = anexos.loaded? ? anexos.find { |anexo| anexo.record_type == 'Attachment' } : anexos.find_by(record_type: 'Attachment')
    dono&.record&.account
  end
end

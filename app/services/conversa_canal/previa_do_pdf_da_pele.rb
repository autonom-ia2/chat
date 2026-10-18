# frozen_string_literal: true

# Gerador da prévia de PDF (#1702) restrito às contas com a pele. O Chatwoot deixa os geradores de prévia
# desligados (`config.active_storage.previewers = []`, #11888); ligar o Poppler para o app inteiro deixaria a
# rota pública de prévia do Active Storage desenhar PDF de qualquer conta. Aqui só aceita o PDF anexado a uma
# mensagem de conta com a pele ligada.
class ConversaCanal::PreviaDoPdfDaPele < ActiveStorage::Previewer::PopplerPDFPreviewer
  def self.accept?(blob)
    super && ConversaCanal::Pele.ligada?(conta_do(blob))
  end

  def self.conta_do(blob)
    blob.attachments.find_by(record_type: 'Attachment')&.record&.account
  end
end

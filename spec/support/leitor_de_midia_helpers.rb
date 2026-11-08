# IA entende a conversa F4: anexos de teste para o leitor de mídia (PDF gerado na hora, com ou sem texto).
module LeitorDeMidiaHelpers
  def pdf_de_teste(texto, nome: 'documento.pdf')
    Prawn::Fonts::AFM.hide_m17n_warning = true
    corpo = Prawn::Document.new.tap { |pdf| texto.present? ? pdf.text(texto) : pdf.stroke_horizontal_rule }.render
    Rack::Test::UploadedFile.new(StringIO.new(corpo), 'application/pdf', original_filename: nome)
  end

  def anexar_pdf(mensagem, texto, nome: 'documento.pdf')
    mensagem.attachments.create!(account: mensagem.account, file_type: :file, file: pdf_de_teste(texto, nome: nome))
  end

  def anexar_imagem(mensagem, meta: {})
    mensagem.attachments.create!(account: mensagem.account, file_type: :image, external_url: 'https://exemplo.invalid/foto.jpg', meta: meta)
  end

  # O contador do teto do dia e a marca de releitura enfileirada ficam no Redis, que não volta entre os exemplos.
  def limpar_redis_do_leitor
    Redis::Alfred.scan_each(match: 'crm:leitor_de_midia:*') { |chave| Redis::Alfred.delete(chave) }
  end

  def anexar_audio(mensagem, meta: {})
    mensagem.attachments.create!(account: mensagem.account, file_type: :audio, external_url: 'https://exemplo.invalid/audio.ogg', meta: meta)
  end
end

RSpec.configure { |config| config.include LeitorDeMidiaHelpers }

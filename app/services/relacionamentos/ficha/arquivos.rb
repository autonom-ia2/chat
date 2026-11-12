# Os arquivos da ficha da pessoa de Relacionamentos (#2895) no formato da tela, do mais novo para trás: nome, tipo e
# quando. São os anexos com arquivo (foto, áudio, vídeo e documento) das conversas que quem pede pode ler
# (Contacts::ConversasLegiveis). Localização, contato e mídia que é só um endereço de fora não têm nome de arquivo.
# Arquivo de nota interna da equipe não entra: a lista é do que foi trocado com a pessoa.
class Relacionamentos::Ficha::Arquivos
  # A tela mostra os mais novos numa lista só, sem "mostrar mais"; o que passa do teto fica de fora.
  TETO = 50
  TIPOS = { 'image' => 'imagem', 'audio' => 'audio', 'video' => 'video', 'file' => 'documento' }.freeze

  def initialize(conversas)
    @conversas = conversas
  end

  def call
    Attachment.where(file_type: TIPOS.keys, message_id: Message.where(conversation_id: @conversas, private: false).select(:id))
              .joins(:file_attachment).preload(file_attachment: :blob)
              .order(created_at: :desc, id: :desc).limit(TETO).map do |anexo|
      { id: anexo.id, nome: anexo.file.filename.to_s, tipo: TIPOS.fetch(anexo.file_type), quando: anexo.created_at.to_i }
    end
  end
end

# Os arquivos da ficha da pessoa de Relacionamentos (#2895) no formato da tela, do mais novo para trás: nome, tipo e
# quando. São os anexos com arquivo (foto, áudio, vídeo e documento) das conversas que quem pede pode ler
# (Contacts::ConversasLegiveis). Localização, contato e mídia que é só um endereço de fora não têm nome de arquivo.
# Arquivo de nota interna da equipe não entra: a lista é do que foi trocado com a pessoa.
#
# #3113: cada arquivo leva o endereço para abrir (`url`, o mesmo da conversa) e a miniatura (`miniatura`). A foto ganha
# uma redução própria, maior que a da conversa (o cartão da ficha é largo e a tela costuma ser de alta densidade); o PDF
# usa a 1ª página que a conversa já mostra (ConversaCanal::PreviaDoPdfNoAnexo, via thumb_url). Sem miniatura (áudio,
# vídeo, planilha, PDF sem prévia, foto que não dá para reduzir), nil: a tela desenha o tipo. O preload dos anexos do
# blob serve a ConversaCanal::PreviaDoPdfDaPele, que acha a conta do PDF sem uma consulta por arquivo.
class Relacionamentos::Ficha::Arquivos
  # A tela mostra os mais novos; o que passa do teto fica de fora.
  TETO = 50
  TIPOS = { 'image' => 'imagem', 'audio' => 'audio', 'video' => 'video', 'file' => 'documento' }.freeze
  # O mesmo tamanho da prévia do PDF: nítido no cartão de ~220 px em tela 2x.
  TAMANHO_DA_FOTO = [600, 600].freeze

  def initialize(conversas)
    @conversas = conversas
  end

  def call
    Attachment.where(file_type: TIPOS.keys, message_id: Message.where(conversation_id: @conversas, private: false).select(:id))
              .joins(:file_attachment).preload(:account, file_attachment: { blob: { attachments: { record: :account } } })
              .order(created_at: :desc, id: :desc).limit(TETO).map { |anexo| para_a_tela(anexo) }
  end

  private

  def para_a_tela(anexo)
    { id: anexo.id, nome: anexo.file.filename.to_s, tipo: TIPOS.fetch(anexo.file_type), quando: anexo.created_at.to_i,
      url: anexo.file_url, miniatura: miniatura(anexo) }
  end

  def miniatura(anexo)
    return anexo.thumb_url.presence unless anexo.image?

    Rails.application.routes.url_helpers.url_for(anexo.file.representation(resize_to_limit: TAMANHO_DA_FOTO))
  rescue ActiveStorage::UnrepresentableError
    nil
  end
end

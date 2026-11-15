# Os PDFs que já chegaram nas conversas de uma pessoa (E6.5, #2899), para "escolher um PDF da conversa" no seguro de outra
# corretora: do mais novo para trás, só das conversas que quem pede pode ler (Contacts::ConversasLegiveis, a regra do
# histórico do contato) e só o que foi trocado com a pessoa (nota interna da equipe não entra). O tipo é o que o
# armazenamento guardou do arquivo; quem lê confere o conteúdo de novo (Carteira::DeFora::Ler).
#
# O nome do arquivo vai para a tela (é o que a pessoa reconhece, como na ficha), nunca para log.
class Carteira::DeFora::Arquivos
  TETO = 20

  def initialize(pessoa, user:)
    @pessoa = pessoa
    @user = user
  end

  def call
    pdfs.limit(TETO).map { |anexo| { id: anexo.id, nome: anexo.file.filename.to_s, quando: anexo.created_at.to_i } }
  end

  # O anexo pedido, só entre os PDFs que esta pessoa pode escolher; nil quando não é um deles.
  def anexo(id)
    pdfs.find_by(id: id)
  end

  private

  def pdfs
    conversas = Contacts::ConversasLegiveis.call(@pessoa.id, user: @user, account: @pessoa.account)
    Attachment.where(account_id: @pessoa.account_id, file_type: 'file',
                     message_id: Message.where(conversation_id: conversas, private: false).select(:id))
              .joins(:file_blob).where(active_storage_blobs: { content_type: Carteira::Pdf::TIPO })
              .preload(file_attachment: :blob).order(created_at: :desc, id: :desc)
  end
end

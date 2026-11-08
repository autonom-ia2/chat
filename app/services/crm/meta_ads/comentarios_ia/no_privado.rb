# IA cuida dos comentários em Agentes (#2481): o grupo "no privado" da gaveta Comentários. Quem recebeu da IA no
# privado, pelas conversas que nasceram do cuidado e que quem abre vê (Painel.enviadas_vistas, as mesmas do número
# `sent`), da mais nova para a mais velha, até LIMITE (o número do grupo conta todas). Cada uma: quem (o contato), o
# comentário (a atividade do topo da conversa, gravada por Conversa#anotar!: o texto já está na caixa, nada é lido na
# Meta), a rede, se a pessoa respondeu e o "Ver conversa" (só para quem enxerga a conversa). A resposta pública da IA
# não entra à parte: ela só responde no comentário depois do privado, na mesma pessoa.
class Crm::MetaAds::ComentariosIa::NoPrivado
  LIMITE = 50
  PAINEL = Crm::MetaAds::ComentariosIa::Painel

  # conversation_access: o mesmo do Painel (o "Ver conversa" só vai quando quem abre a tela vê a conversa).
  def initialize(account:, care:, viewer:, conversation_access:)
    @account = account
    @care = care
    @viewer = viewer
    @conversation_access = conversation_access
  end

  def call
    return [] if @care.nil?

    conversas = PAINEL.enviadas_vistas(@account, [@care.id.to_s], @viewer).includes(:contact)
                      .reorder(created_at: :desc, id: :desc).limit(LIMITE).to_a
    responderam = Conversation.where(id: conversas.map(&:id)).where(PAINEL.respondeu.arel.exists).pluck(:id)
    no_topo = comentario_no_topo(conversas.map(&:id))
    conversas.map { |conversation| linha(conversation, no_topo, responderam) }
  end

  private

  def linha(conversation, no_topo, responderam)
    { id: conversation.display_id, contato: conversation.contact&.name, comentario: no_topo[conversation.id],
      network: conversation.additional_attributes.to_h.dig('meta_ads_comment', 'network'),
      respondeu: responderam.include?(conversation.id), conversation_path: caminho(conversation) }
  end

  # A primeira atividade de cada conversa: o comentário que a abriu ("Comentou no post: …").
  def comentario_no_topo(ids)
    Message.where(conversation_id: ids, message_type: :activity).reorder(:conversation_id, :created_at, :id)
           .select('DISTINCT ON (messages.conversation_id) messages.conversation_id, messages.content')
           .to_h { |message| [message.conversation_id, message.content] }
  end

  def caminho(conversation)
    return unless @conversation_access.call(conversation)

    "/app/accounts/#{conversation.account_id}/conversations/#{conversation.display_id}"
  end
end

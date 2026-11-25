# A ENTREGA DO COMPARATIVO EM PDF na conversa (#3211): gera o PDF da cotação e o posta UMA vez por cotação, sem
# legenda (quem fala junto do arquivo é a Lia). Com responsável na conversa vira nota privada, como a entrega das
# ferramentas assíncronas.
#
# UMA VEZ POR COTAÇÃO (R7): o marcador `autonomia_comparativo_viagem` (o id da cotação) vai no `content_attributes` da
# PRÓPRIA mensagem do PDF, e a conferência é feita sob o lock da conversa, SEM filtrar `private`: o PDF pode ter saído
# público ou como nota, e nos dois casos ele já conta.
#
# NUNCA LEVANTA: é entrega sobre uma conversa que já funciona; falha vira log com ids e classe, e `false`.
class Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  CHAVE = 'autonomia_comparativo_viagem'.freeze
  NOME_DO_ARQUIVO = 'comparativo-seguro-viagem.pdf'.freeze

  # -> true quando o PDF foi postado agora; false quando já existia ou falhou.
  def self.postar(conversation:, cotacao:, agent:)
    new(conversation: conversation, cotacao: cotacao, agent: agent).postar
  end

  def initialize(conversation:, cotacao:, agent:)
    @conversation = conversation
    @cotacao = cotacao
    @agent = agent
  end

  def postar
    return false if postado?

    postou = false
    # O lock é numa cópia lida agora: a conversa do turno pode ter atributos alterados em memória, e o Rails recusa
    # travar registro com mudança não gravada.
    @conversation = @conversation.class.find(@conversation.id)
    @conversation.with_lock { postou = criar_se_nova }
    postou
  rescue StandardError => e
    Rails.logger.warn("[autonomia][seguro_viagem] comparativo_falhou conv=#{@conversation&.id} cotacao=#{@cotacao&.id} " \
                      "agente=#{@agent&.id} #{e.class}")
    false
  end

  # O `content_attributes` é `store` (texto serializado): o `LIKE` é a peneira barata, e quem decide é a comparação
  # exata do id da cotação.
  def postado?
    @conversation.messages.where('content_attributes::text LIKE ?', "%#{CHAVE}%")
                 .any? { |message| message.content_attributes.to_h[CHAVE].to_i == @cotacao.id }
  end

  def criar(blob)
    agent_inbox = ::Autonomia::Agents::QuemResponde.agent_inbox(@conversation)
    Messages::MessageBuilder.new(
      nil, @conversation,
      ActionController::Parameters.new(
        content: nil, attachments: [blob.signed_id], message_type: 'outgoing',
        sender_type: 'AgentBot', sender_id: agent_inbox&.agent_bot_id,
        private: @conversation.assignee_id.present?,
        content_attributes: { 'autonomia_agent_id' => @agent.id, CHAVE => @cotacao.id }
      )
    ).perform
  end

  private

  # O blob só nasce depois da conferência sob o lock: dois turnos juntos não deixam arquivo órfão.
  def criar_se_nova
    return false if postado?

    blob = gravar_blob
    begin
      criar(blob).present?
    rescue StandardError
      blob.purge
      raise
    end
  end

  def gravar_blob
    nome = @agent.marca_do_contratado.to_h['nome_corretora']
    pdf = SeguroViagem::ComparativoPdf.new(cotacao: @cotacao, nome_corretora: nome).render
    ActiveStorage::Blob.create_and_upload!(io: StringIO.new(pdf), filename: NOME_DO_ARQUIVO,
                                           content_type: 'application/pdf')
  end
end

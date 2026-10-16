# O convite do motor de entrega venceu sem ninguém pegar. Chamado pela fila (Crm::Ai::HandoffDrainJob), dentro da
# transação da rodada.
#
# - Os administradores da caixa são avisados (#1140, decisão 8), uma vez só na espera (Crm::Entrega::AvisoSemNinguem).
# - Conversa que espera pessoa (o robô pediu pessoa ou saiu de vez, e o convite seguiu, #1694): a regra roda de novo
#   deixando de fora quem já deixou vencer (decisão do Rodrigo de 16/10, opção "a"), guardado na marca (`venceram`).
#   Ex.: a Ana deixou vencer, o Bruno é convidado; ele deixou vencer, a Carla. Sem ninguém que sobre, segura esperando
#   alguém online, sem convite novo. Pessoa fixa da regra que deixou vencer: a regra cai para quem cuida do funil.
# - Robô no comando (o convite da IA do CRM com o robô atendendo, sem pedir pessoa): a marca sai e os administradores
#   são avisados, sem rodar a regra.
#
# Relido sob a trava. Já com pessoa no nome, resolvida ou fechada: a marca vencida sai, sem aviso (senão ficaria
# pendurada, a fila voltaria a ela a cada rodada e o rodízio nativo a pularia depois). Adiada: guarda a marca (volta à
# fila quando reabre), sem aviso.
class Crm::Entrega::ConviteVencido
  def initialize(conversation)
    @conversation = conversation
  end

  def call
    venceram = nil
    @conversation.with_lock do
      next unless Crm::Entrega::Marca.convite_vencido?(@conversation)
      next if @conversation.snoozed?

      venceram = vencer
      @conversation.save!
    end
    # Ainda dentro da transação da rodada: a trava da conversa só sai no commit, e ninguém assume entre a marca e a regra.
    return if venceram.nil?

    marca = Crm::Entrega::Marca.dados(@conversation)
    Crm::Entrega.new(conversation: @conversation, motivo: marca['motivo'], origem: 'fila', excluir: venceram).call
  end

  private

  # Na memória (quem chama grava). Devolve quem deixou vencer quando a regra roda de novo; nil quando a marca só sai.
  def vencer
    venceram = esperando_pessoa? && @conversation.awaiting_person? ? segurar : nil
    Crm::Entrega::Marca.tirar(@conversation) if venceram.nil?
    avisar if esperando_pessoa?
    venceram
  end

  def esperando_pessoa?
    @conversation.assignee_id.nil? && (@conversation.open? || @conversation.pending?)
  end

  # A marca vira "segurando", com quem deixou vencer somado, e devolve essa lista. Com o robô à espera, foi ele quem
  # pediu pessoa (o convite da IA do CRM seguiu, #1694): o motivo passa a ser o pedido dele, e a fila não confunde a
  # espera com a da IA do CRM que um agente nosso assumiu (#1673).
  def segurar
    marca = Crm::Entrega::Marca.dados(@conversation)
    venceram = (Array(marca['venceram']) + [convidado(marca)]).compact.map(&:to_i).uniq
    Crm::Entrega::Marca.marcar(@conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo(marca),
                                              falha: Crm::Entrega::AvisoSemNinguem::CONVITE_VENCIDO, venceram: venceram)
    venceram
  end

  def motivo(marca)
    return 'robo_pediu' if @conversation.bot_handoff_waiting?

    marca['motivo'].presence || 'convite_vencido'
  end

  # Quem foi convidado: a marca guarda desde o #1694; a marca de antes dele, só o ciclo do convite no card.
  def convidado(marca)
    marca['convidado_id'].presence || Crm::Assunto.funil_atual(@conversation)&.metadata.to_h.dig('ai', 'handoff', 'invited_agent_id')
  end

  # Savepoint próprio: uma falha no aviso não desfaz a marca (a conversa ficaria presa fora do rodízio, tentada a cada
  # rodada); fica no rastreador e no log, só com ids.
  def avisar
    card = Crm::Assunto.funil_atual(@conversation)
    Conversation.transaction(requires_new: true) do
      Crm::Entrega::AvisoSemNinguem.new(conversation: @conversation, card: card).convite_vencido!
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.error("[crm][entrega] fila conversa=#{@conversation.id} aviso_convite_vencido_falhou erro=#{e.class}")
  end
end

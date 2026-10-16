# O convite do motor de entrega venceu sem ninguém pegar (#1140, decisão 8 do Rodrigo em 16/10/2026). Chamado pela fila
# (Crm::Ai::HandoffDrainJob): a marca sai (o rodízio nativo deixa de pular a conversa) e os administradores da caixa
# são avisados (Crm::Entrega::AvisoSemNinguem#convite_vencido!).
#
# Relido sob a trava. Já com pessoa no nome, resolvida ou fechada: a marca vencida sai, sem aviso (senão ficaria
# pendurada, a fila voltaria a ela a cada rodada e o rodízio nativo a pularia depois). Adiada: guarda a marca (volta à
# fila quando reabre), sem aviso.
class Crm::Entrega::ConviteVencido
  def initialize(conversation)
    @conversation = conversation
  end

  def call
    @conversation.with_lock do
      next unless Crm::Entrega::Marca.convite_vencido?(@conversation)
      next if @conversation.snoozed?

      avisa = esperando_pessoa?
      Crm::Entrega::Marca.tirar(@conversation)
      @conversation.save!
      avisar if avisa
    end
  end

  private

  def esperando_pessoa?
    @conversation.assignee_id.nil? && (@conversation.open? || @conversation.pending?)
  end

  # Savepoint próprio: uma falha no aviso não devolve a marca (a conversa ficaria presa fora do rodízio, tentada a cada
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

# O convite do motor de entrega venceu sem ninguém pegar. Chamado pela fila (Crm::Ai::HandoffDrainJob), dentro da
# transação da rodada.
#
# - Os administradores da caixa são avisados (#1140, decisão 8), uma vez só na espera (Crm::Entrega::AvisoSemNinguem).
# - Conversa que espera pessoa (o robô pediu pessoa ou saiu de vez, e o convite seguiu, #1694): a regra roda de novo
#   deixando de fora quem já deixou vencer (decisão do Rodrigo de 16/10, opção "a"), guardado na marca (`venceram`).
#   Ex.: a Ana deixou vencer, o Bruno é convidado; ele deixou vencer, a Carla. Sem ninguém que sobre, segura esperando
#   alguém online, sem convite novo.
# - Convite da IA do CRM com o robô ainda no comando: só perde a marca (o rodízio nativo deixa de pular a conversa).
#
# Relido sob a trava: quem pegou nesse meio tempo fica com a conversa, e a adiada guarda a marca (volta à fila quando
# reabre); nas duas, nada muda e nada é avisado.
class Crm::Entrega::ConviteVencido
  def initialize(conversation)
    @conversation = conversation
  end

  def call
    venceram = nil
    @conversation.with_lock do
      next unless Crm::Entrega::Marca.convite_vencido?(@conversation) && esperando_pessoa?

      venceram = segurar_ou_soltar
      avisar
      @conversation.save!
    end
    # Ainda dentro da transação da rodada: a trava da conversa só sai no commit, e ninguém assume entre a marca e a regra.
    return if venceram.nil?

    marca = Crm::Entrega::Marca.dados(@conversation)
    Crm::Entrega.new(conversation: @conversation, motivo: marca['motivo'], origem: 'fila', excluir: venceram).call
  end

  private

  def esperando_pessoa?
    @conversation.assignee_id.nil? && (@conversation.open? || @conversation.pending?)
  end

  # Na memória (quem chama grava). Esperando pessoa: a marca vira "segurando", com quem deixou vencer somado, e devolve
  # essa lista. Robô no comando: a marca sai, e devolve nil.
  def segurar_ou_soltar
    marca = Crm::Entrega::Marca.dados(@conversation)
    unless @conversation.awaiting_person?
      Crm::Entrega::Marca.tirar(@conversation)
      return
    end

    venceram = (Array(marca['venceram']) + [marca['convidado_id']]).compact.map(&:to_i).uniq
    Crm::Entrega::Marca.marcar(@conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: marca['motivo'].presence || 'convite_vencido',
                                              falha: Crm::Entrega::AvisoSemNinguem::CONVITE_VENCIDO, venceram: venceram)
    venceram
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

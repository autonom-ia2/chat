# O convite do motor de entrega venceu sem ninguém pegar. Chamado pela fila (Crm::Ai::HandoffDrainJob), dentro da
# transação da rodada.
#
# - Os administradores da caixa são avisados (#1140, decisão 8), uma vez só na espera (Crm::Entrega::AvisoSemNinguem).
# - Conversa que espera pessoa (o robô pediu pessoa ou saiu de vez, e o convite seguiu, #1694): a regra roda de novo
#   deixando de fora quem já deixou vencer (decisão do Rodrigo de 16/10, opção "a"), guardado na marca (`venceram`).
#   Ex.: a Ana deixou vencer, o Bruno é convidado; ele deixou vencer, a Carla. Se todos deixaram vencer, sem convite
#   novo: a conversa vai para o primeiro de quem cuida que ficar online (inclusive quem deixou vencer), pela presença a
#   cada rodada. Pessoa fixa da regra que deixou vencer: a regra cai para quem cuida do funil.
# - Robô no comando (o convite da IA do CRM com o robô atendendo, sem pedir pessoa): a marca sai e os administradores
#   são avisados, sem rodar a regra.
# - Convite pela regra do card a que o cliente ligou o pedido, fora do foco (#1693, `card_id` na marca): a marca segue
#   com o card, a regra roda de novo pela regra DELE e o aviso vai para ele (o Bruno de Vendas não entra no convite de
#   Sinistros).
#
# Relido sob a trava. Já com pessoa no nome, resolvida ou fechada: a marca vencida sai, sem aviso (senão ficaria
# pendurada, a fila voltaria a ela a cada rodada e o rodízio nativo a pularia depois). Adiada: guarda a marca (volta à
# fila quando reabre), sem aviso.
class Crm::Entrega::ConviteVencido
  # Ninguém na fila de quem cuida (todos saíram da caixa ou do funil) depois de convites vencidos: não há a quem
  # entregar, e a presença não muda isso. A fila tenta de novo só depois deste intervalo (alguém pode ter passado a
  # cuidar do funil), e não a cada rodada de 2 minutos. Segurar por presença segue a cada rodada.
  ESPERA_SEM_NINGUEM = 30.minutes
  # `convite_vencido`: a marca que o próprio vencimento grava, quando a regra em seguida não a regrava.
  SEM_NINGUEM = %w[ninguem_cuida nao_conseguimos_chamar convite_vencido].freeze

  # A fila (HandoffDrainJob) pula esta conversa nesta rodada? Só a espera sem ninguém de quem já deixou vencer, e só
  # dentro do intervalo. Segurando por presença ("ninguém online") ou pelo intervalo entre convites segue a cada rodada.
  def self.espacar?(marca)
    return false if marca['venceram'].blank? || SEM_NINGUEM.exclude?(marca['falha'])

    decidido = Time.zone.parse(marca['decidido_em'].to_s)
    decidido.present? && decidido > ESPERA_SEM_NINGUEM.ago
  rescue ArgumentError
    false
  end

  def initialize(conversation)
    @conversation = conversation
  end

  def call
    venceram = nil
    @card = Crm::Entrega::Marca.card(@conversation)
    @conversation.with_lock do
      next unless Crm::Entrega::Marca.convite_vencido?(@conversation)
      next if @conversation.snoozed?

      venceram = vencer
      @conversation.save!
    end
    # Ainda dentro da transação da rodada: a trava da conversa só sai no commit, e ninguém assume entre a marca e a regra.
    return if venceram.nil?

    marca = Crm::Entrega::Marca.dados(@conversation)
    Crm::Entrega.new(conversation: @conversation, motivo: marca['motivo'], origem: 'fila', excluir: venceram, card: @card,
                     pelo_card: @card.present?).call
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
  # espera com a da IA do CRM que um agente nosso assumiu (#1673). Sem saber quem deixou vencer (lista vazia), nil: a
  # marca sai, como no robô no comando, em vez de a regra rodar sem ninguém de fora e reconvidar a mesma pessoa.
  def segurar
    marca = Crm::Entrega::Marca.dados(@conversation)
    venceram = (Array(marca['venceram']) + [convidado(marca)]).compact.map(&:to_i).uniq
    return if venceram.empty?

    Crm::Entrega::Marca.marcar(@conversation, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo(marca),
                                              falha: Crm::Entrega::AvisoSemNinguem::CONVITE_VENCIDO, venceram: venceram, card: @card)
    venceram
  end

  def motivo(marca)
    return 'robo_pediu' if @conversation.bot_handoff_waiting?

    marca['motivo'].presence || 'convite_vencido'
  end

  # Quem foi convidado: a marca guarda desde o #1694; a marca de antes dele, só o ciclo do convite no card (o do pedido,
  # quando a marca o traz, #1693; senão o do foco).
  def convidado(marca)
    marca['convidado_id'].presence || (@card || Crm::Assunto.funil_atual(@conversation))&.metadata.to_h.dig('ai', 'handoff', 'invited_agent_id')
  end

  # Savepoint próprio: uma falha no aviso não desfaz a marca (a conversa ficaria presa fora do rodízio, tentada a cada
  # rodada); fica no rastreador e no log, só com ids.
  def avisar
    card = @card if Crm::Assunto.da_conversa?(@card, @conversation)
    card ||= Crm::Assunto.funil_atual(@conversation)
    Conversation.transaction(requires_new: true) do
      Crm::Entrega::AvisoSemNinguem.new(conversation: @conversation, card: card).convite_vencido!
    end
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: @conversation.account).capture_exception
    Rails.logger.error("[crm][entrega] fila conversa=#{@conversation.id} aviso_convite_vencido_falhou erro=#{e.class}")
  end
end

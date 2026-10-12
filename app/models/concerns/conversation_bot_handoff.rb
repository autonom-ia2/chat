# PASSAGEM DO ROBÔ PARA PESSOA (#1377, decisões do Rodrigo em 12/10).
#
# O robô passa a conversa (`bot_handoff!`): ela abre e o rodízio tenta uma pessoa na hora. Sem ninguém agora, o robô
# segue no nome da conversa e respondendo, e a conversa fica marcada "à espera de pessoa" (BOT_HANDOFF_WAITING_SINCE_KEY).
# Com a marca:
#   - o rodízio continua a enxergá-la (`awaiting_person`) e a entrega quando houver alguém;
#   - a resposta do robô não a tira de "Não atendidas" (Message#clear_waiting_since_on_outgoing_response);
#   - o agente Autonom.ia não registra uma segunda passagem (Autonomia::Agents::Operate.espelho_no_comando?).
# A marca sai quando uma pessoa entra na conversa (é o "assumiu"), quando ela é resolvida ou quando alguém a entrega
# de novo a um robô.
module ConversationBotHandoff
  extend ActiveSupport::Concern

  BOT_HANDOFF_WAITING_SINCE_KEY = 'bot_handoff_waiting_since'.freeze
  # O que a passagem lê ou regrava, trazido da linha travada (take_fresh_assignee).
  FRESH_ON_HANDOFF = %w[assignee_id assignee_agent_bot_id ai_assignee_type additional_attributes].freeze
  # Sem robô no nome, ou com robô e à espera de pessoa (contador de não lidas por atribuição).
  WITHOUT_BOT_OR_WAITING_SQL = '(conversations.assignee_agent_bot_id IS NULL OR ' \
                               "conversations.additional_attributes ->> '#{BOT_HANDOFF_WAITING_SINCE_KEY}' IS NOT NULL)".freeze
  # Sem pessoa no nome: as sem dono e as que o robô passou e seguem à espera de pessoa. É o que o rodízio distribui e,
  # desde a decisão do Rodrigo em 12/10 (opção b), também a aba "Não atribuídas" e a contagem dela.
  AWAITING_PERSON_SQL = "(conversations.assignee_id IS NULL AND #{WITHOUT_BOT_OR_WAITING_SQL})".freeze

  included do
    scope :awaiting_person, -> { where(AWAITING_PERSON_SQL) }

    before_save :end_bot_handoff_wait, if: -> { bot_handoff_waiting? && (assignee_id.present? || resolved?) }
  end

  # `keep_bot: false` solta o robô de vez: é o caminho de quem desliga o robô, não de quem passa a conversa.
  # Uma gravação só, com a linha travada: quem chega primeiro (uma pessoa assumindo, outra passagem) decide.
  def bot_handoff!(dispatch_event: true, keep_bot: true)
    self.class.transaction do
      take_fresh_assignee
      robo = keep_bot ? handoff_bot : nil
      self.waiting_since = Time.current if waiting_since.blank?
      self.ai_assignee = nil
      self.status = :open
      assign_person_on_handoff
      if robo && assignee_id.blank?
        wait_for_person_with(robo)
      else
        end_bot_handoff_wait
      end
      save!
    end
    enqueue_auto_assignment_after_handoff
    dispatch_bot_handoff_event if dispatch_event
  end

  def bot_handoff_waiting?
    additional_attributes.is_a?(Hash) && additional_attributes[BOT_HANDOFF_WAITING_SINCE_KEY].present?
  end

  # O mesmo critério do scope `awaiting_person`, para um registro só: aba "Não atribuídas", contagens e permissões.
  def awaiting_person?
    assignee_id.nil? && (assignee_agent_bot_id.nil? || bot_handoff_waiting?)
  end

  def end_bot_handoff_wait
    self.additional_attributes = additional_attributes.except(BOT_HANDOFF_WAITING_SINCE_KEY)
  end

  # O robô ativo da caixa, quando há.
  def inbox_agent_bot
    inbox.agent_bot_inbox&.active? ? inbox.agent_bot : nil
  end

  def dispatch_bot_handoff_event
    dispatcher_dispatch(Events::Types::CONVERSATION_BOT_HANDOFF)
  end

  private

  # Trava a linha numa cópia lida do banco (o próprio registro pode trazer mudança não gravada, que o `with_lock`
  # recusa) e traz dela o que esta passagem lê ou regrava — quem está no nome e os atributos adicionais, para não
  # apagar uma chave gravada por outra conexão —, sem marcar como mudança. O mesmo que
  # AgentAssignmentService#assign_under_lock faz com o assignee.
  # Contrato: quem chama não deixa mudança não gravada nesses atributos; ela seria descartada.
  def take_fresh_assignee
    locked = self.class.lock.find(id)
    FRESH_ON_HANDOFF.each { |attribute| self[attribute] = locked[attribute] }
    clear_attribute_changes(FRESH_ON_HANDOFF)
  end

  def handoff_bot
    ai_assignee.is_a?(AgentBot) ? ai_assignee : inbox_agent_bot
  end

  # Rodízio antigo (V1): roda aqui, na mesma gravação, porque a conversa de robô já está aberta e a troca de status
  # que o dispararia não acontece.
  def assign_person_on_handoff
    return if inbox.auto_assignment_v2_enabled?
    return unless should_run_auto_assignment?

    AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: legacy_allowed_agent_ids).assign_under_lock
  end

  def wait_for_person_with(robo)
    self.ai_assignee = robo
    self.additional_attributes = additional_attributes.merge(BOT_HANDOFF_WAITING_SINCE_KEY => Time.current.iso8601)
  end

  # Rodízio novo (V2): o job lê o banco, então só depois do commit.
  def enqueue_auto_assignment_after_handoff
    return unless assignee_id.blank? && inbox.auto_assignment_v2_enabled? && inbox.enable_auto_assignment?

    inbox_id_to_assign = inbox_id
    ActiveRecord.after_all_transactions_commit { AutoAssignment::AssignmentJob.enqueue_for_inbox(inbox_id_to_assign) }
  end
end

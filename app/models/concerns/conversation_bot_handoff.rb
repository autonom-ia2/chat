# PASSAGEM DO ROBÔ PARA PESSOA (#1377, decisões do Rodrigo em 12/10; motor de entrega do #1454, 13/10).
#
# O robô passa a conversa (`bot_handoff!`): ela abre e o motor único de entrega (Crm::Entrega) escolhe quem a recebe
# na hora, pela regra da Atribuição do funil do card ou, sem ela, para quem cuida da conversa, está online e tem menos
# conversas abertas. O rodízio nativo da caixa não é chamado daqui: a entrega acontece com ele ligado ou desligado.
# Sem ninguém agora, o robô segue no nome da conversa e respondendo, e a conversa fica marcada "à espera de pessoa"
# (BOT_HANDOFF_WAITING_SINCE_KEY), além da marca do motor (Crm::Entrega::Marca) quando ele segura ou convida.
# Com a marca de espera:
#   - a conversa segue em "Não atribuídas" (`awaiting_person`) e o motor a entrega quando alguém ficar online
#     (HandoffDrainJob);
#   - a resposta do robô não a tira de "Não atendidas" (Message#clear_waiting_since_on_outgoing_response);
#   - o agente Autonom.ia não registra uma segunda passagem (Autonomia::Agents::Operate.espelho_no_comando?).
# As marcas saem quando uma pessoa entra na conversa (é o "assumiu"), quando ela é resolvida ou quando alguém a entrega
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
    # O que o rodízio nativo pode pegar: sem a marca do motor de entrega (#1454).
    scope :outside_crm_delivery, -> { where(Crm::Entrega::Marca::AUSENTE_SQL) }

    before_save :end_bot_handoff_wait, if: -> { (bot_handoff_waiting? || crm_delivery_pending?) && (assignee_id.present? || resolved?) }
  end

  # `keep_bot: false` solta o robô de vez: é o caminho de quem desliga o robô, não de quem passa a conversa.
  # `motivo`: por que a conversa precisa de alguém (log do motor de entrega).
  # `release_assignee`: tira quem atende na mesma gravação (saída da triagem): uma gravação só por passagem.
  # Uma gravação só, com a linha travada: quem chega primeiro (uma pessoa assumindo, outra passagem) decide.
  # A regra da Atribuição pode apontar um agente de IA (#1593): a passagem grava como se esperasse pessoa e, depois do
  # commit de TODAS as transações abertas (quem chama pode estar dentro de uma trava), o motor passa ao agente
  # (Crm::Entrega#concluir_para_ia!), com o robô que passou como origem. Com o agente no comando, não há aviso de
  # passagem para pessoa; recusado, o motor entrega a alguém da equipe e o aviso sai como sempre.
  # O motivo da passagem vai no contexto do registro de passagens (#1606): a pessoa entra no save daqui, depois que a
  # Entrega já saiu, e a conversa prende o motivo nesse save (ConversationPassagem).
  def bot_handoff!(dispatch_event: true, keep_bot: true, motivo: nil, release_assignee: false)
    motivo ||= keep_bot ? 'robo_pediu' : 'robo_desligado'
    para_ia, quem_passou = Crm::Passagens.com_motivo(motivo) do
      passar_ao_atendimento!(keep_bot: keep_bot, motivo: motivo, release_assignee: release_assignee)
    end
    depois_da_passagem(para_ia, dispatch_event, quem_passou, motivo)
  end

  def passar_ao_atendimento!(keep_bot:, motivo:, release_assignee:)
    para_ia = nil
    quem_passou = nil
    self.class.transaction do
      take_fresh_assignee(release_assignee)
      quem_passou = handoff_bot
      robo = keep_bot ? quem_passou : nil
      self.waiting_since = Time.current if waiting_since.blank?
      self.ai_assignee = nil
      self.status = :open
      para_ia = deliver_on_handoff(motivo, keep_bot, quem_passou)
      robo && assignee_id.blank? ? wait_for_person_with(robo) : clear_bot_wait_mark
      save!
    end
    [para_ia, quem_passou]
  end
  private :passar_ao_atendimento!

  def bot_handoff_waiting?
    additional_attributes.is_a?(Hash) && additional_attributes[BOT_HANDOFF_WAITING_SINCE_KEY].present?
  end

  def crm_delivery_pending?
    Crm::Entrega::Marca.presente?(self)
  end

  # O mesmo critério do scope `awaiting_person`, para um registro só: aba "Não atribuídas", contagens e permissões.
  def awaiting_person?
    assignee_id.nil? && (assignee_agent_bot_id.nil? || bot_handoff_waiting?)
  end

  # Encerra a espera de pessoa e a do motor de entrega.
  def end_bot_handoff_wait
    clear_bot_wait_mark
    Crm::Entrega::Marca.tirar(self)
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
  def take_fresh_assignee(release_assignee)
    locked = self.class.lock.find(id)
    FRESH_ON_HANDOFF.each { |attribute| self[attribute] = locked[attribute] }
    clear_attribute_changes(FRESH_ON_HANDOFF)
    self.assignee = nil if release_assignee
  end

  def handoff_bot
    ai_assignee.is_a?(AgentBot) ? ai_assignee : inbox_agent_bot
  end

  # Sem agente de IA na regra, o aviso de passagem sai na hora, como sempre. Com ele, tudo espera o commit.
  def depois_da_passagem(para_ia, dispatch_event, quem_passou, motivo)
    if para_ia
      ActiveRecord.after_all_transactions_commit { concluir_passagem(para_ia, dispatch_event, quem_passou, motivo) }
    elsif dispatch_event
      dispatch_bot_handoff_event
    end
  end

  # Depois do commit: a passagem ao agente de IA que a regra apontou. Com ele no comando, sem aviso de passagem.
  # Um erro aqui sai depois do commit de quem chamou: fica no log, a conversa fica com a marca de segurar (a fila tenta
  # de novo) e o aviso de passagem sai, como numa recusa.
  def concluir_passagem(para_ia, dispatch_event, quem_passou, motivo)
    com_ia = para_ia.concluir_para_ia!(origem: quem_passou).status == :com_ia
    dispatch_bot_handoff_event if dispatch_event && !com_ia
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] concluir passagem ao agente falhou conversa=#{id} erro=#{e.class}")
    segurar_para_a_fila(motivo)
    dispatch_bot_handoff_event if dispatch_event
  end

  # Sem a marca do motor, a fila (HandoffDrainJob) não veria a conversa. Relida sob a trava: quem entrou nesse meio tempo
  # (uma pessoa, o agente de IA, a resolução) vence, e nada é gravado. Numa cópia lida do banco: a que falhou pode ter
  # mudança só na memória.
  def segurar_para_a_fila(motivo)
    conversa = self.class.find(id)
    conversa.with_lock do
      next unless conversa.awaiting_person? && !conversa.resolved?

      Crm::Entrega::Marca.marcar(conversa, modo: Crm::Entrega::Marca::SEGURANDO, motivo: motivo, falha: 'erro_na_passagem')
      conversa.save!
    end
  rescue StandardError => e
    Rails.logger.error("[crm][entrega] segurar para a fila falhou conversa=#{id} erro=#{e.class}")
  end

  # O motor de entrega (#1454), na mesma gravação da passagem: a pessoa escolhida entra junto com a abertura, e a
  # marca de quem segura ou convida também. Já com pessoa no nome (a IA do CRM entregou antes), não há o que entregar.
  # Devolve a entrega quando ela aponta um agente de IA (#1593), para terminar depois do commit.
  def deliver_on_handoff(motivo, keep_bot, quem_passou)
    return if assignee_id.present?

    motivo ||= keep_bot ? 'robo_pediu' : 'robo_desligado'
    entrega = Crm::Entrega.new(conversation: self, motivo: motivo, origem: 'passagem', quem_passou: quem_passou)
    entrega if entrega.na_passagem.status == :para_ia
  end

  def wait_for_person_with(robo)
    self.ai_assignee = robo
    self.additional_attributes = additional_attributes.merge(BOT_HANDOFF_WAITING_SINCE_KEY => Time.current.iso8601)
  end

  def clear_bot_wait_mark
    self.additional_attributes = additional_attributes.except(BOT_HANDOFF_WAITING_SINCE_KEY)
  end
end

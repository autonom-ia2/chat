# Memória das IAs (#1601): a cada 5 minutos, refaz o que os eventos não fizeram (job que falhou, listener que não
# rodou). Só nas contas com a flag `memoria_ia`. Idempotente: tarefa uma por conversa, bilhete só onde não há.
#   1. passagem IA/robô -> pessoa das últimas 24 h, conversa aberta, sem tarefa que a conheça e sem resposta de pessoa
#      depois dela (os filtros vão no SQL: o que já foi resolvido não é relido a cada ciclo);
#   2. conversa segurada pela Entrega sem tarefa aberta;
#   3. passagem das últimas 24 h sem bilhete (nunca a do contato apagado) ou com a reserva da IA esquecida.
# Quando refaz tarefa ou bilhete que faltava, deixa a contagem no log e no rastreador (o caminho principal falhou).
class Crm::Memoria::ConciliacaoJob < ApplicationJob
  queue_as :scheduled_jobs
  JANELA = 24.hours

  SEM_TAREFA_DA_PASSAGEM = <<~SQL.squish.freeze
    NOT EXISTS (SELECT 1 FROM crm_follow_ups f WHERE f.account_id = crm_passagens.account_id
      AND f.conversation_id = crm_passagens.conversation_id
      AND (f.metadata #> '{memoria,passagem_ids}') @> to_jsonb(crm_passagens.id))
  SQL
  SEM_RESPOSTA_DEPOIS = <<~SQL.squish.freeze
    NOT EXISTS (SELECT 1 FROM crm_mensagem_origens o JOIN messages m ON m.id = o.message_id
      WHERE o.account_id = crm_passagens.account_id AND o.conversation_id = crm_passagens.conversation_id
      AND o.autor_tipo IN ('pessoa_painel', 'pessoa_celular') AND o.foi_ao_cliente AND NOT o.encaminhada
      AND m.created_at >= crm_passagens.em)
  SQL
  SEM_TAREFA_ABERTA = <<~SQL.squish.freeze
    NOT EXISTS (SELECT 1 FROM crm_follow_ups f WHERE f.account_id = conversations.account_id
      AND f.conversation_id = conversations.id AND f.status IN (0, 3)
      AND (f.metadata #>> '{memoria,tipo}') = 'retomar_atendimento')
  SQL

  def perform
    return unless Crm::Config.enabled?

    Account.feature_memoria_ia.find_each { |account| conciliar(account) }
  end

  private

  # Uma conta que falha não para as outras.
  def conciliar(account)
    refeitas = tarefas_de_passagem(account) + tarefas_de_segurada(account)
    refeitos = bilhetes(account)
    liberar_reservas_esgotadas(account)
    alertar(account, refeitas, refeitos) if (refeitas + refeitos).positive?
  rescue StandardError => e
    Rails.logger.error("[crm][memoria][conciliacao] conta=#{account.id} erro=#{e.class}")
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  def tarefas_de_passagem(account)
    total = 0
    passagens_recentes(account).where(para_type: 'User', de_type: Crm::Memoria::Compromissos::DE_IA)
                               .where.not(motivo: Crm::Passagens::CONVITE)
                               .joins(:conversation).where(conversations: { status: %i[open pending] })
                               .where(SEM_TAREFA_DA_PASSAGEM).where(SEM_RESPOSTA_DEPOIS).includes(:conversation).find_each do |passagem|
      total += 1 if Crm::Memoria::Compromissos.abrir_retomada!(conversation: passagem.conversation, origem: 'passagem', passagem: passagem)
    end
    total
  end

  def tarefas_de_segurada(account)
    total = 0
    Conversation.where(account_id: account.id, assignee_id: nil, status: %i[open pending])
                .where(Crm::Entrega::Marca::PRESENTE_SQL).where(SEM_TAREFA_ABERTA).find_each do |conversa|
      marca = Crm::Entrega::Marca.dados(conversa)
      next unless marca && marca['modo'] == Crm::Entrega::Marca::SEGURANDO

      total += 1 if Crm::Memoria::Compromissos.abrir_retomada!(conversation: conversa, origem: 'segurada')
    end
    total
  end

  def bilhetes(account)
    total = 0
    passagens_recentes(account).where(bilhete: nil).where('bilhete_status IS DISTINCT FROM ?', Crm::Memoria::Bilhete::APAGADO)
                               .includes(:conversation).find_each do |passagem|
      next unless Crm::Memoria.ativa?(passagem.conversation)

      total += 1 if Crm::Memoria::Bilhete.fallback!(passagem).to_i.positive?
      Crm::Memoria::BilheteJob.perform_later(passagem.id)
    end
    reservas_esquecidas(account).find_each { |passagem| Crm::Memoria::BilheteJob.perform_later(passagem.id) }
    total
  end

  def reservas_esquecidas(account)
    passagens_recentes(account).where(bilhete_status: 'gerando', bilhete_reservado_em: ...Crm::Memoria::Bilhete::RESERVA_VALE.ago)
                               .where(bilhete_tentativas: ...Crm::Memoria::Bilhete::TENTATIVAS)
  end

  # Reserva esquecida sem tentativa sobrando: volta ao bilhete do código, de vez (sem alerta a cada ciclo).
  def liberar_reservas_esgotadas(account)
    passagens_recentes(account).where(bilhete_status: 'gerando', bilhete_reservado_em: ...Crm::Memoria::Bilhete::RESERVA_VALE.ago)
                               .where(bilhete_tentativas: Crm::Memoria::Bilhete::TENTATIVAS..)
                               .update_all(bilhete_status: 'fallback', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def passagens_recentes(account)
    Crm::Passagem.where(account_id: account.id, created_at: JANELA.ago..)
  end

  def alertar(account, tarefas, bilhetes)
    texto = "[crm][memoria][conciliacao] conta=#{account.id} tarefas=#{tarefas} bilhetes=#{bilhetes}"
    Rails.logger.warn(texto)
    ChatwootExceptionTracker.new(StandardError.new(texto), account: account).capture_exception
  end
end

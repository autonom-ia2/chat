# Arquivar um card, o mesmo caminho para a pessoa (Api::V1::Accounts::Crm::CardsController#destroy), o lote
# (Crm::Cards::BulkAction) e a IA (Crm::Ai::NaoENegocio e o aceite do "era teste", Crm::Ai::FecharCard::Aceite).
#
# Arquivado, o card não tem mais o que fazer: as sugestões de etapa da IA pendentes expiram; os lembretes, tarefas e
# follow-ups ainda por vencer são cancelados (motivo `card_archived`, o mesmo que o DueProcessor usa); e o lembrete que
# repete deixa de repetir. O card ganho ou perdido continua nos Números (Crm::Card::DESFECHO_ARQUIVADO).
#
# A reunião marcada com o cliente NÃO é cancelada: cancelar avisa o cliente (convite do calendário ou WhatsApp), e isso
# é decisão de quem atende, pela tela da reunião. Ela fica, com o lembrete dela, e a atividade do arquivamento registra
# quais ficaram (`reunioes_mantidas`).
#
# Ordem das travas, a mesma do resto do CRM: série, lembretes, card. O SeriesMaterializer trava a série antes de criar a
# vez; o DueProcessor trava o lembrete e depois o card (Crm::FollowUps::AutoFollowupRunner); o reset do follow-up da IA
# também (CardsController#reset_auto_followup). Travar o card primeiro e o lembrete depois cruzaria com eles
# (ActiveRecord::Deadlocked). O card é relido sob a trava: o status de agora decide o desfecho guardado, não o do objeto
# carregado antes (outro pedido pode ter fechado o card como Ganho nesse meio tempo).
class Crm::Cards::Archiver
  MOTIVO = 'card_archived'.freeze

  def initialize(card:, actor:, payload: {})
    @card = card
    @actor = actor
    @payload = payload.to_h
    @now = Time.current
  end

  # true quando arquivou; false quando o card já estava arquivado (nada muda, nada é registrado). O bloco, quando há,
  # roda sob as travas, com o card relido, e decide se ainda arquiva (as guardas da IA); false desiste sem arquivar.
  def perform
    ActiveRecord::Base.transaction do
      travar_series
      travar_lembretes
      @card.lock!
      next false if (block_given? && !yield) || @card.archived?

      # Relidos sob a trava do card: entra o que foi criado entre uma trava e outra (criar série ou lembrete do card
      # espera a trava do card até o fim desta transação).
      arquivar!(travar_series, travar_lembretes)
      true
    end
  end

  private

  def travar_series
    Crm::FollowUpSeries.where(account_id: @card.account_id, card_id: @card.id, status: %i[active paused]).order(:id).lock.to_a
  end

  def travar_lembretes
    @card.follow_ups.active.where.not(id: reunioes_mantidas.filter_map(&:reminder_id)).order(:id).lock.to_a
  end

  # A série encerra antes de as vezes serem canceladas, e travada desde o começo: o SeriesMaterializer, que trava a série
  # para criar a vez seguinte, espera e a encontra encerrada. Nenhuma vez nova nasce depois do cancelamento.
  def arquivar!(series, lembretes)
    @card.update!(status: :archived, last_activity_at: @now)
    expirar_sugestoes!
    encerrar_series!(series)
    cancelar_lembretes!(lembretes)
    Crm::FollowUps::CardNextDueUpdater.update(@card)
    Crm::ActivityLogger.new(card: @card, actor: @actor, event_type: 'archive', payload: registro(lembretes.size)).perform
  end

  def expirar_sugestoes!
    @card.account.crm_ai_stage_suggestions.where(card: @card, status: :pending).find_each { |sugestao| sugestao.update!(status: :expired) }
  end

  def encerrar_series!(series)
    series.each { |serie| serie.update!(status: :ended, ended_at: @now) }
  end

  def cancelar_lembretes!(lembretes)
    lembretes.each do |lembrete|
      lembrete.update!(status: :canceled, canceled_at: @now, metadata: lembrete.metadata.to_h.merge('canceled_reason' => MOTIVO))
    end
  end

  def reunioes_mantidas
    @reunioes_mantidas ||= Crm::Meeting.where(account_id: @card.account_id, card_id: @card.id).upcoming.to_a
  end

  def registro(cancelados)
    extra = {}
    extra[:lembretes_cancelados] = cancelados if cancelados.positive?
    extra[:reunioes_mantidas] = reunioes_mantidas.map(&:id) if reunioes_mantidas.any?
    @payload.merge(extra)
  end
end

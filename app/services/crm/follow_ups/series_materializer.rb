# #1460 — cria a próxima vez de uma série ativa como uma linha normal em crm_follow_ups. Uma vez pendente por série:
# enquanto a vez marcada não passou (o DueProcessor a marca como atrasada e avisa) nem foi feita, nada novo nasce.
# Vezes perdidas (job parado, série pausada) não voltam: a próxima é a primeira depois de agora. A primeira vez da
# série vale mesmo no passado, porque foi a pessoa que escolheu o dia.
# Sem próxima vez (fim da série), a série é encerrada. A série fica travada (with_lock) enquanto isso, para pausar ou
# encerrar ao mesmo tempo não criar vez numa série parada.
class Crm::FollowUps::SeriesMaterializer
  def initialize(series, now: Time.current)
    @series = series
    @now = now
  end

  def perform
    follow_up = @series.with_lock { materialize }
    return if follow_up.nil?

    Crm::FollowUps::CardNextDueUpdater.update(@series.card)
    Crm::Cards::Broadcaster.broadcast(@series.card, Events::Types::CRM_CARD_UPDATED)
    follow_up
  end

  private

  # Card arquivado não ganha vez nova: a série que o Crm::Cards::Archiver não pegou (travada aqui) se encerra, sob a
  # trava dela. O status vem da barreira do arquivamento (série -> card, a ordem de sempre).
  def materialize
    return unless @series.active?
    return finish_series if @series.card_id && Crm::Cards::Archiver.arquivado_sob_trava?(@series.card_id)
    return if @series.follow_ups.pending.exists?

    occurrence = @series.schedule.next_after(start_from)
    return finish_series if occurrence.nil?

    create_follow_up(occurrence)
  end

  def start_from
    last = @series.follow_ups.maximum(:occurrence_at)
    return @series.starts_at - 1.second if last.nil?

    [last, @now].max
  end

  # Savepoint: a mesma vez criada por outro processo (índice único) não aborta a transação de quem chamou.
  def create_follow_up(occurrence)
    @series.transaction(requires_new: true) do
      @series.follow_ups.create!(
        links.merge(@series.slice(:title, :description, :timezone, :recipient_mode, :recipient_user_ids, :recipient_team_id))
             .merge(follow_up_type: :task, automation_mode: :reminder_only, due_at: occurrence, occurrence_at: occurrence)
      )
    end
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def links
    card = @series.card
    {
      account_id: @series.account_id, card: card, conversation_id: @series.conversation_id,
      contact_id: @series.contact_id || card&.contact_id, company_id: @series.company_id, inbox_id: card&.inbox_id,
      assignee_id: @series.occurrence_assignee_id, created_by_id: @series.created_by_id
    }
  end

  def finish_series
    @series.update!(status: :ended, ended_at: @now)
    nil
  end
end

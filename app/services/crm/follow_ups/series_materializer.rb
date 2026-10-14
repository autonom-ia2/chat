# #1460 — cria a próxima vez de uma série ativa como uma linha normal em crm_follow_ups. Uma vez pendente por série:
# enquanto a vez marcada não passou (o DueProcessor a marca como atrasada e avisa) nem foi feita, nada novo nasce.
# Vezes perdidas (job parado, série pausada) não voltam: a próxima é a primeira depois de agora. A primeira vez da
# série vale mesmo no passado, porque foi a pessoa que escolheu o dia.
# Sem próxima vez (fim da série), a série é encerrada.
class Crm::FollowUps::SeriesMaterializer
  def initialize(series, now: Time.current)
    @series = series
    @now = now
  end

  def perform
    return unless @series.active?
    return if @series.follow_ups.pending.exists?

    occurrence = @series.schedule.next_after(start_from)
    return finish_series if occurrence.nil?

    follow_up = create_follow_up(occurrence)
    Crm::FollowUps::CardNextDueUpdater.update(@series.card)
    Crm::Cards::Broadcaster.broadcast(@series.card, Events::Types::CRM_CARD_UPDATED)
    follow_up
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  private

  def start_from
    last = @series.follow_ups.maximum(:occurrence_at)
    return @series.starts_at - 1.second if last.nil?

    [last, @now].max
  end

  def create_follow_up(occurrence)
    @series.follow_ups.create!(
      links.merge(@series.slice(:title, :description, :timezone, :recipient_mode, :recipient_user_ids, :recipient_team_id))
           .merge(follow_up_type: :task, automation_mode: :reminder_only, due_at: occurrence, occurrence_at: occurrence)
    )
  end

  def links
    card = @series.card
    {
      account_id: @series.account_id, card: card, conversation_id: @series.conversation_id,
      contact_id: @series.contact_id || card&.contact_id, company_id: @series.company_id, inbox_id: card&.inbox_id,
      assignee_id: assignee_id, created_by_id: @series.created_by_id
    }
  end

  def assignee_id
    return @series.card&.owner_id || @series.created_by_id if @series.recipients_card_owner?

    @series.created_by_id
  end

  def finish_series
    @series.update!(status: :ended, ended_at: @now)
    nil
  end
end

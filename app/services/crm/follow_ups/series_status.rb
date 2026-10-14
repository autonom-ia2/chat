# #1460 — pausar, retomar e encerrar um lembrete que repete (decisões do Rodrigo, 14/10/2026):
# - pausar não apaga datas: a série fica "Pausada" e ninguém é avisado (o DueProcessor deixa passar a vez em
#   silêncio enquanto a série estiver pausada);
# - retomar volta a criar vezes a partir de agora;
# - encerrar para de repetir: a vez que ainda não aconteceu é cancelada e o que já foi feito fica no histórico.
class Crm::FollowUps::SeriesStatus
  def initialize(series:, user:, now: Time.current)
    @series = series
    @user = user
    @now = now
  end

  def pause
    changed = @series.with_lock { @series.active? && @series.update!(status: :paused, paused_at: @now) }
    return @series unless changed

    after_change('follow_up_series_paused')
  end

  def resume
    changed = @series.with_lock { @series.paused? && @series.update!(status: :active, paused_at: nil) }
    return @series unless changed

    Crm::FollowUps::SeriesMaterializer.new(@series, now: @now).perform
    after_change('follow_up_series_resumed')
  end

  def finish
    finished = @series.with_lock do
      next false if @series.ended?

      @series.update!(status: :ended, ended_at: @now)
      @series.follow_ups.pending.find_each do |follow_up|
        follow_up.update!(status: :canceled, canceled_at: @now, metadata: follow_up.metadata.merge('canceled_reason' => 'series_ended'))
      end
      true
    end
    return @series unless finished

    after_change('follow_up_series_ended')
  end

  private

  def after_change(event_type)
    card = @series.card
    Crm::FollowUps::CardNextDueUpdater.update(card)
    Crm::ActivityLogger.new(card: card, actor: @user, event_type: event_type,
                            payload: { series_id: @series.id, title: @series.title, status: @series.status }).perform
    Crm::Cards::Broadcaster.broadcast(card, Events::Types::CRM_CARD_UPDATED)
    @series
  end
end

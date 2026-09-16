module EmailCampaigns
  module DirectInbox
    # Motor de envio direto com THROTTLE humano: 1 e-mail por "tick", reagenda o próximo
    # com intervalo aleatório (60-120s), só em horário comercial (9-18h, dias úteis),
    # respeitando o teto diário da caixa e com auto-pausa por falhas. Sem SES.
    class DeliveryEngine
      TIMEZONE = 'America/Sao_Paulo'.freeze

      def initialize(campaign)
        @campaign = campaign
        @inbox = campaign.sender_inbox
        @account = campaign.account
      end

      def tick
        return if @campaign.recipient_import_active?
        return finalize if no_pending?
        return if pause_if_guardrail_or_autopause!
        return reschedule(seconds_until_next_window) unless within_business_hours?
        return reschedule(seconds_until_next_window) if daily_cap_reached?

        recipient = next_pending
        return finalize if recipient.nil?

        RecipientSender.new(@campaign, Sender.new(@inbox)).deliver(recipient)

        @campaign.reload
        return finalize if @campaign.sending? && no_pending?

        reschedule(random_interval) if @campaign.sending?
      end

      private

      def next_pending
        @campaign.email_campaign_recipients.pending.order(:id).first
      end

      def no_pending?
        !@campaign.email_campaign_recipients.pending.exists?
      end

      def finalize
        @campaign.finalize! if @campaign.reload.sending?
      end

      def reschedule(seconds)
        TickJob.set(wait: seconds.seconds).perform_later(@campaign.id)
      end

      def random_interval
        rand(Limits::MIN_INTERVAL_SECONDS..Limits::MAX_INTERVAL_SECONDS)
      end

      # ---- horário comercial (fuso BR) ----
      def within_business_hours?
        now = Time.current.in_time_zone(TIMEZONE)
        now.on_weekday? && now.hour >= Limits::BUSINESS_HOUR_START && now.hour < Limits::BUSINESS_HOUR_END
      end

      def seconds_until_next_window
        now = Time.current.in_time_zone(TIMEZONE)
        target = now.change(hour: Limits::BUSINESS_HOUR_START, min: 0, sec: 0)
        target += 1.day if now.hour >= Limits::BUSINESS_HOUR_START
        target += 1.day until target.on_weekday?
        [(target - now).to_i, 60].max
      end

      # ---- teto diário rolling 24h por caixa ----
      def daily_cap_reached?
        sent_last_24h >= Limits.daily_cap(@inbox.channel.email)
      end

      def sent_last_24h
        EmailCampaignRecipient
          .joins(:email_campaign)
          .where(email_campaigns: { sender_inbox_id: @inbox.id })
          .where(email_campaign_recipients: { sent_at: 24.hours.ago.. })
          .count
      end

      # ---- guardrail + auto-pausa ----
      def pause_if_guardrail_or_autopause!
        if EmailCampaigns::Guardrail.paused?(@account)
          pause!('guardrail de reputação da conta')
          return true
        end
        if autopause_tripped?
          pause!('muitas falhas de envio seguidas — verifique a caixa e a lista de contatos')
          return true
        end
        false
      end

      def autopause_tripped?
        # Carrega os registros e usa o predicado .failed? (robusto: pluck de enum pode vir
        # como string OU inteiro dependendo do adapter). O limite é pequeno (3), barato.
        recent = @campaign.email_campaign_recipients
                          .where(status: %i[sent failed])
                          .order(updated_at: :desc)
                          .limit(Limits::AUTOPAUSE_CONSECUTIVE_FAILURES)
                          .to_a
        consecutive = recent.size == Limits::AUTOPAUSE_CONSECUTIVE_FAILURES && recent.all?(&:failed?)

        processed = @campaign.sent_count.to_i + @campaign.failed_count.to_i
        rate = processed >= 20 && (@campaign.failed_count.to_f / processed) >= Limits::AUTOPAUSE_FAILURE_RATE

        consecutive || rate
      end

      def pause!(reason)
        @campaign.update!(status: :paused, last_error: "Envio pausado: #{reason}.")
      end
    end
  end
end

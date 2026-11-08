module EmailCampaigns
  module DirectInbox
    # Motor de envio direto com THROTTLE humano: 1 e-mail por "tick", reagenda o próximo
    # com intervalo aleatório (60-120s), só em horário comercial (9-18h, dias úteis),
    # respeitando o teto diário da caixa e com auto-pausa por falhas. Sem SES.
    class DeliveryEngine
      TIMEZONE = 'America/Sao_Paulo'.freeze
      CHAIN_KEY = 'email_campaigns:direct_inbox:next_tick:%<campaign_id>d'.freeze
      # The key only marks the newest chain; it expires a little after its tick's time, so it never outlives the chain.
      CHAIN_GRACE = 10.minutes

      def initialize(campaign)
        @campaign = campaign
        @inbox = campaign.sender_inbox
      end

      # Each tick schedules the next one with a token (#2722); a scheduled tick whose token is no longer the
      # campaign's latest belongs to a duplicated chain and stops, so the human rhythm holds with one chain.
      def tick(token = nil)
        EmailCampaigns::Reputation::CampaignDeliveryLock.synchronize(@campaign.id) do
          deliver_tick if chain_turn?(token) && @campaign.reload.sending?
        end
      end

      # A campanha aberta (#2717) só acorda o envio quando não há tick agendado (CampaignJourney::CampanhaAberta).
      def self.tick_scheduled?(campaign)
        Redis::Alfred.get(chain_key(campaign.id)).present?
      end

      def self.chain_key(campaign_id)
        format(CHAIN_KEY, campaign_id: campaign_id)
      end

      private

      def deliver_tick
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

      def next_pending
        CampaignJourney::CampanhaAberta.a_enviar(@campaign).order(:id).first
      end

      def no_pending?
        !CampaignJourney::CampanhaAberta.a_enviar(@campaign).exists?
      end

      def chain_turn?(token)
        return true if token.nil?

        # Runs under the campaign delivery lock, like reschedule: read and delete do not interleave with another tick.
        # Only a newer chain stops this tick. With no key (expired by a late queue, or the chain ended) it goes on.
        key = self.class.chain_key(@campaign.id)
        latest = Redis::Alfred.get(key)
        return false if latest.present? && latest != token

        Redis::Alfred.delete(key) if latest.present?
        true
      end

      def finalize
        @campaign.finalize! if @campaign.reload.sending?
      end

      def reschedule(seconds)
        token = SecureRandom.uuid
        Redis::Alfred.set(self.class.chain_key(@campaign.id), token, ex: (seconds.seconds + CHAIN_GRACE).to_i)
        TickJob.set(wait: seconds.seconds).perform_later(@campaign.id, token)
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
        return true if EmailCampaigns::Reputation::Admission.new(@campaign).park_if_blocked!

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
        @campaign.with_delivery_lock do
          next unless @campaign.sending? || @campaign.scheduled?

          @campaign.update!(status: :paused, pause_reason: { kind: 'technical', code: 'direct_inbox_autopause' },
                            last_error: "Envio pausado: #{reason}.")
        end
      end
    end
  end
end

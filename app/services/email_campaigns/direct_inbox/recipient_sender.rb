module EmailCampaigns
  module DirectInbox
    # Entrega para 1 destinatário no modo direto: render + tracking (pixel/clique) + envio
    # pela caixa + claim/persist. Espelha o deliver_one do DeliveryEngine (SES), mas isolado
    # para NÃO mexer no caminho SES que já funciona. Reusa o mesmo tracking, então abertura/
    # clique/descadastro entram no MESMO dashboard.
    class RecipientSender
      def initialize(campaign, sender)
        @campaign = campaign
        @sender = sender
      end

      # Returns :sent, :failed, :suppressed, :paused or :skipped. A stale Set is ignored.
      def deliver(recipient, _suppressed = nil)
        gate = ::EmailCampaigns::DeliveryClaim.new(@campaign)
        result = gate.prepare(recipient)
        return result unless result == :ready

        rendered = render(recipient)
        tracked_html = ::EmailCampaigns::Tracking::Injector.new(recipient, rendered[:body_html]).perform
        headers = unsubscribe_headers(recipient)
        result = gate.claim(recipient)
        claimed = result == :claimed
        return result unless claimed

        message_id = dispatch(recipient, rendered, tracked_html, headers)
        persist_sent(recipient, message_id)
        :sent
      rescue StandardError => e
        Rails.logger.error("[DirectInbox::RecipientSender] campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
        handle_send_failure(recipient, e) if claimed
        :failed
      ensure
        @campaign.refresh_counters!
      end

      private

      def dispatch(recipient, rendered, tracked_html, headers)
        @sender.deliver(
          to: recipient.email, subject: rendered[:subject], html_body: tracked_html,
          from_email: @campaign.from_email, reply_to: @campaign.reply_to.presence || @campaign.from_email, headers: headers
        )
      end

      def handle_send_failure(recipient, error)
        ::EmailCampaigns::Reputation::Admission.new(@campaign).with_delivery_locks(recipient) do
          recipient.mark_failed!(error.message) if recipient.sent? && recipient.sent_at.nil? && recipient.ses_message_id.blank?
        end
      end

      # Persistência pós-envio com rescue próprio: se o envio deu certo mas o UPDATE falhar,
      # o destinatário PERMANECE :sent (claim) — nunca reenfileira (evitaria duplicado).
      def persist_sent(recipient, message_id)
        ::EmailCampaigns::Reputation::Admission.new(@campaign).with_delivery_locks(recipient) do
          recipient.update_columns(ses_message_id: message_id, sent_at: Time.current, last_error: nil, updated_at: Time.current)
        end
        register_delivered(recipient, message_id)
      rescue StandardError => e
        Rails.logger.error("[DirectInbox::RecipientSender] post-send persist failed campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
      end

      # No envio direto NÃO existe webhook de entrega (SES tem SNS; webmail não). O aceite do
      # provedor (Graph 202 / SMTP OK) É o sinal de entrega. Registra o evento 'delivered'
      # (idempotente, espelha Sns::EventProcessor#on_delivery) para alimentar delivered_count,
      # as taxas (abertura/clique são calculadas sobre entregues) e a série temporal.
      def register_delivered(recipient, message_id)
        ::EmailCampaigns::Reputation::Admission.new(@campaign).with_delivery_locks(recipient) do
          return if recipient.email_events.where(event_type: :delivered).exists?

          recipient.email_events.create!(event_type: :delivered, occurred_at: Time.current,
                                         payload: { 'via' => 'direct_inbox', 'message_id' => message_id })
          recipient.mark_delivered!
        end
      end

      def render(recipient)
        renderer = ::EmailCampaigns::TemplateRenderer.new(recipient)
        { subject: renderer.render(@campaign.subject), body_html: renderer.render(@campaign.body_html) }
      end

      def unsubscribe_headers(recipient)
        url = ::EmailCampaigns::Unsubscribe::Token.url(recipient)
        { 'List-Unsubscribe' => "<#{url}>", 'List-Unsubscribe-Post' => 'List-Unsubscribe=One-Click' }
      end
    end
  end
end

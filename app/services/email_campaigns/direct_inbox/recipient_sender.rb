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

      # Retorna :sent, :failed, :suppressed ou :skipped.
      def deliver(recipient, suppressed)
        if suppressed.include?(recipient.email.downcase)
          EmailCampaignRecipient.where(id: recipient.id, status: :pending).update_all(status: EmailCampaignRecipient.statuses[:suppressed])
          return :suppressed
        end
        # claim() faz a transição atômica pending->sent. A partir daqui o destinatário JÁ
        # está marcado como enviado: garantia at-most-once. Falha de envio marca FAILED e
        # NUNCA volta para pending — reenvio por uma caixa pessoal gera duplicado e risco de
        # bloqueio. Auto-pause cuida de padrões de falha.
        return :skipped unless claim(recipient)

        send_claimed(recipient)
      ensure
        @campaign.refresh_counters!
      end

      private

      def send_claimed(recipient)
        rendered = render(recipient)
        tracked_html = ::EmailCampaigns::Tracking::Injector.new(recipient, rendered[:body_html]).perform
        message_id = @sender.deliver(
          to: recipient.email,
          subject: rendered[:subject],
          html_body: tracked_html,
          from_email: @campaign.from_email,
          reply_to: @campaign.reply_to.presence || @campaign.from_email,
          headers: unsubscribe_headers(recipient)
        )
        persist_sent(recipient, message_id)
        :sent
      rescue StandardError => e
        Rails.logger.error("[DirectInbox::RecipientSender] campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
        recipient.mark_failed!(e.message)
        :failed
      end

      # Persistência pós-envio com rescue próprio: se o envio deu certo mas o UPDATE falhar,
      # o destinatário PERMANECE :sent (claim) — nunca reenfileira (evitaria duplicado).
      def persist_sent(recipient, message_id)
        recipient.update_columns(ses_message_id: message_id, sent_at: Time.current, last_error: nil, updated_at: Time.current)
        register_delivered(recipient, message_id)
      rescue StandardError => e
        Rails.logger.error("[DirectInbox::RecipientSender] post-send persist failed campaign=#{@campaign.id} recipient=#{recipient.id} #{e.message}")
      end

      # No envio direto NÃO existe webhook de entrega (SES tem SNS; webmail não). O aceite do
      # provedor (Graph 202 / SMTP OK) É o sinal de entrega. Registra o evento 'delivered'
      # (idempotente, espelha Sns::EventProcessor#on_delivery) para alimentar delivered_count,
      # as taxas (abertura/clique são calculadas sobre entregues) e a série temporal.
      def register_delivered(recipient, message_id)
        return if recipient.email_events.where(event_type: :delivered).exists?

        recipient.email_events.create!(event_type: :delivered, occurred_at: Time.current,
                                       payload: { 'via' => 'direct_inbox', 'message_id' => message_id })
        recipient.mark_delivered!
      end

      def claim(recipient)
        claimed = ::EmailCampaigns::Reputation::Admission.new(@campaign).claim!(recipient)
        # update_all não toca a instância em memória: sincroniza para que mark_delivered!
        # (que exige sent?/delivered?) enxergue o novo status em vez do :pending obsoleto.
        recipient.status = :sent if claimed
        claimed
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

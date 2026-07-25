module EmailCampaigns
  module Ai
    # Tick leve de polling do pedido em background. Cada execução é sub-segundo (um GET na OpenAI)
    # e se re-agenda até completar. Idempotente: carrega o `token` da geração e TODA escrita no
    # model é guardada por ele — se uma nova geração substituiu esta, este poll vira no-op (não
    # persiste mjml/erro velhos). Teto de ~10 min.
    class PollJob < ApplicationJob
      queue_as :medium

      POLL_INTERVAL = 8.seconds
      # ~15 min de teto: a geração típica leva ~2-3 min, mas a fila da OpenAI (gpt-5.6-sol high em
      # background) pode passar de 10 min em picos — headroom evita timeout falso. Ticks são baratos.
      MAX_ATTEMPTS = 113

      def perform(campaign_id, token, response_id, attempt)
        campaign = EmailCampaign.find_by(id: campaign_id)
        return if campaign.blank? || !active?(campaign, token)

        return finish_failed(campaign, token, response_id, 'timeout') if attempt >= MAX_ATTEMPTS

        credential = Crm::Ai::CredentialResolver.new(account: campaign.account).resolve
        return finish_failed(campaign, token, response_id, 'ai_not_configured') if credential.blank?

        client = Crm::Ai::ResponsesClient.new(credential: credential)
        handle_status(campaign, client, token, response_id, attempt, client.retrieve(response_id))
      rescue Crm::Ai::ResponsesClient::Error => e
        # Falha transitória de rede: continua tentando (limitado) em vez de falhar de imediato.
        raise_or_retry(campaign, token, response_id, attempt, e)
      end

      private

      def active?(campaign, token)
        campaign.ai_processing? && campaign.ai_generation_token == token
      end

      def handle_status(campaign, client, token, response_id, attempt, result)
        case result[:status]
        when 'completed'
          finish_completed(campaign, client, token, response_id, result[:text], result[:usage])
        when 'failed', 'cancelled', 'incomplete'
          finish_failed(campaign, token, response_id, result[:error].presence || result[:status], client)
        else # queued, in_progress
          reschedule(campaign.id, token, response_id, attempt)
        end
      end

      def raise_or_retry(campaign, token, response_id, attempt, error)
        return if campaign.blank?

        if attempt + 1 >= MAX_ATTEMPTS
          finish_failed(campaign, token, response_id, error.message)
        else
          reschedule(campaign.id, token, response_id, attempt)
        end
      end

      def reschedule(campaign_id, token, response_id, attempt)
        self.class.set(wait: POLL_INTERVAL).perform_later(campaign_id, token, response_id, attempt + 1)
      end

      def finish_completed(campaign, client, token, response_id, text, usage = {})
        parsed = parse_output(text)
        # Resposta completa mas sem mjml utilizável: NÃO marca pronto (o Sanitizer transformaria
        # nil num e-mail só com rodapé). Trata como falha p/ o usuário poder tentar de novo.
        return finish_failed(campaign, token, response_id, 'empty_response', client) if parsed.nil?

        mjml = EmailCampaigns::Ai::Sanitizer.new(parsed['mjml']).perform
        # Não persiste MJML acima do cap do model (update_all pula a validação de tamanho — evita
        # gravar algo que depois quebraria o save no editor). Improvável p/ e-mail, mas defensivo.
        return finish_failed(campaign, token, response_id, 'generation_too_large', client) if mjml.to_s.length > EmailCampaign::BODY_HTML_MAX

        won = campaign.ai_succeed!(token, subject: parsed['subject'], preheader: parsed['preheader'],
                                          body_mjml: mjml, subject_variants: parsed['subject_variants'])
        # Telemetria de consumo só na transição idempotente vencedora (evita evento duplicado
        # se dois ticks vissem 'completed'). Os tokens já foram gastos na geração concluída.
        if won
          Crm::Ai::UsageRecorder.record(
            account: campaign.account, feature: 'email', model: Crm::Ai::Config::MODEL_EMAIL,
            usage: usage, reasoning_effort: 'high'
          )
        end
        client.delete(response_id)
        Broadcaster.ready(campaign) if won
      end

      def parse_output(text)
        parsed = JSON.parse(text.to_s)
        return nil unless parsed.is_a?(Hash) && parsed['mjml'].to_s.strip.present?

        parsed
      rescue JSON::ParserError, TypeError
        nil
      end

      def finish_failed(campaign, token, response_id, message, client = nil)
        won = campaign.ai_fail!(token, message)
        client&.delete(response_id)
        Broadcaster.failed(campaign) if won
      end
    end
  end
end

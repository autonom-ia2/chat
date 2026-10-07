module EmailCampaigns
  module Ai
    # Tick leve de polling do pedido em background. Cada execução é sub-segundo (um GET na OpenAI)
    # e se re-agenda até completar. Idempotente: carrega o `token` da geração e TODA escrita no
    # model é guardada por ele — se uma nova geração substituiu esta, este poll vira no-op (não
    # persiste mjml/erro velhos). Teto de ~15 min.
    #
    # Controle de qualidade (#1076): o e-mail pronto passa pelo QualityCheck. Se algo falha, o modelo
    # recebe o e-mail e o relatório UMA vez para corrigir (um novo pedido em background, acompanhado por
    # este mesmo job com options['repaired']). Depois da correção, o que impede o envio faz a geração
    # falhar ('quality_gate_failed'); o resto é gravado como aviso para a pessoa.
    #
    # options: { 'brand_identity' => {...}, 'placeholders' => [...], 'repaired' => bool }. Jobs já
    # enfileirados antes do #1076 chegam sem options e seguem como antes (sem identidade nem controle).
    class PollJob < ApplicationJob
      queue_as :medium

      POLL_INTERVAL = 8.seconds
      # ~15 min de teto: a geração típica leva ~2-3 min, mas a fila da OpenAI (modelo de e-mail high em
      # background) pode passar de 10 min em picos — headroom evita timeout falso. Ticks são baratos.
      MAX_ATTEMPTS = 113
      REPAIR_EFFORT = 'medium'.freeze

      # One tick: the campaign, the generation token and the provider response it follows.
      Run = Struct.new(:campaign, :token, :response_id, :attempt, :client)

      def perform(campaign_id, token, response_id, attempt, options = {})
        @options = options.to_h.stringify_keys
        campaign = EmailCampaign.find_by(id: campaign_id)
        return if campaign.blank? || !active?(campaign, token)

        @run = Run.new(campaign, token, response_id, attempt)
        return finish_failed('timeout') if attempt >= MAX_ATTEMPTS

        credential = Crm::Ai::CredentialResolver.new(account: campaign.account).resolve
        return finish_failed('ai_not_configured') if credential.blank?

        @run.client = Crm::Ai::ResponsesClient.new(credential: credential)
        handle_status(@run.client.retrieve(response_id))
      rescue Crm::Ai::ResponsesClient::Error => e
        # Falha transitória de rede: continua tentando (limitado) em vez de falhar de imediato.
        raise_or_retry(e)
      end

      private

      def active?(campaign, token)
        campaign.ai_processing? && campaign.ai_generation_token == token
      end

      def handle_status(result)
        case result[:status]
        when 'completed'
          finish_completed(result)
        when 'failed', 'cancelled', 'incomplete'
          finish_failed(result[:error].presence || result[:status])
        else # queued, in_progress
          reschedule(@run.response_id)
        end
      end

      def raise_or_retry(error)
        return if @run.nil?

        @run.attempt + 1 >= MAX_ATTEMPTS ? finish_failed(error.message) : reschedule(@run.response_id)
      end

      def reschedule(response_id)
        self.class.set(wait: POLL_INTERVAL).perform_later(@run.campaign.id, @run.token, response_id, @run.attempt + 1, @options)
      end

      def finish_completed(result)
        adjustment = Adjustment.find(@run.campaign, @run.token)
        return finish_adjustment(adjustment, result) if adjustment

        parsed = parse_output(result[:text])
        # Resposta completa mas sem mjml utilizável: NÃO marca pronto (o Sanitizer transformaria
        # nil num e-mail só com rodapé). Trata como falha p/ o usuário poder tentar de novo.
        return finish_failed('empty_response') if parsed.nil?

        mjml = EmailCampaigns::Ai::Sanitizer.new(parsed['mjml']).perform
        # Não persiste MJML acima do cap do model (update_all pula a validação de tamanho — evita
        # gravar algo que depois quebraria o save no editor). Improvável p/ e-mail, mas defensivo.
        return finish_failed('generation_too_large') if mjml.to_s.length > EmailCampaign::BODY_HTML_MAX

        draft = parsed.merge('mjml' => mjml)
        check = quality_check(mjml)
        return request_repair(draft, check, result) if check.repair? && !@options['repaired']
        return finish_failed('quality_gate_failed') if check.blocking.any?

        succeed(draft, check, result)
      end

      # "Ajustar com IA" (#1095): the answer is a proposal the editor shows; AdjustFinisher checks and keeps it.
      def finish_adjustment(adjustment, result)
        AdjustFinisher.new(campaign: @run.campaign, token: @run.token, client: @run.client, response_id: @run.response_id,
                           adjustment: adjustment).call(text: result[:text], usage: result[:usage], model: result.fetch(:model))
      end

      def succeed(draft, check, result)
        campaign = @run.campaign
        variants = SubjectVariants.new(draft['subject_variants'])
        warnings = check.warnings.map { |warning| { 'check' => warning.check.to_s, 'detail' => warning.detail } }
        won = campaign.ai_succeed!(
          @run.token,
          { subject: draft['subject'], preheader: draft['preheader'], body_mjml: draft['mjml'], subject_variants: variants.variants },
          brand_identity: @options['brand_identity'] || {}, quality_warnings: [*warnings, variants.warning].compact
        )
        # Telemetria de consumo só na transição idempotente vencedora (evita evento duplicado
        # se dois ticks vissem 'completed'). Os tokens já foram gastos na geração concluída.
        record_usage(result) if won
        EmailCampaigns::Ai::Broadcaster.ready(campaign) if won
        @run.client.delete(@run.response_id)
      end

      # Pede a correção e passa a acompanhar o novo pedido. A troca do response_id é guardada (só um tick
      # vence); quem perde apaga o pedido que abriu.
      def request_repair(draft, check, result)
        client = @run.client
        repair = client.create_background(model: Crm::Ai::Config::MODEL_EMAIL, instructions: PromptBuilder.repair,
                                          input: repair_input(draft, check), schema: Generator::GENERATE_SCHEMA,
                                          reasoning_effort: REPAIR_EFFORT)
        return finish_failed('empty_response') if repair[:id].blank?
        return client.delete(repair[:id]) unless @run.campaign.ai_swap_response!(@run.token, from: @run.response_id, to: repair[:id])

        record_usage(result)
        @options = @options.merge('repaired' => true)
        reschedule(repair[:id])
        client.delete(@run.response_id)
      end

      def repair_input(draft, check)
        placeholders = (EmailCampaigns::TemplateValidator::DEFAULT_KEYS + Array(@options['placeholders'])).uniq
        text = "E-MAIL (dado):\n#{JSON.generate(draft.slice('subject', 'preheader', 'subject_variants', 'mjml'))}\n\n" \
               "PROBLEMAS A CORRIGIR:\n#{check.report}\n\n" \
               "PLACEHOLDERS PERMITIDOS: #{placeholders.map { |key| "{{ #{key} }}" }.join(', ')}"
        [{ role: 'user', content: [{ type: 'input_text', text: text }] }]
      end

      # Pedidos enfileirados antes do #1076 (sem options) terminam como antes, sem o controle.
      def quality_check(mjml)
        return QualityCheck::Result.new([]) unless @options.key?('placeholders')

        QualityCheck.new(mjml, placeholders: @options['placeholders']).call
      end

      def record_usage(result)
        Crm::Ai::UsageRecorder.record(
          account: @run.campaign.account, feature: 'email', model: result.fetch(:model),
          usage: result[:usage], reasoning_effort: @options['repaired'] ? REPAIR_EFFORT : 'high'
        )
      end

      def parse_output(text)
        parsed = JSON.parse(text.to_s)
        return nil unless parsed.is_a?(Hash) && parsed['mjml'].to_s.strip.present?

        parsed
      rescue JSON::ParserError, TypeError
        nil
      end

      def finish_failed(message)
        won = @run.campaign.ai_fail!(@run.token, message)
        EmailCampaigns::Ai::Broadcaster.failed(@run.campaign) if won
        @run.client&.delete(@run.response_id)
      end
    end
  end
end

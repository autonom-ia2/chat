module EmailCampaigns
  module Ai
    # Submete a geração de e-mail à OpenAI em modo BACKGROUND (retorna na hora um response_id que
    # a OpenAI processa do lado dela) e agenda o PollJob. Não segura thread por minutos; sobrevive
    # a deploy/restart (a OpenAI continua gerando e o poll recupera pelo response_id). Carrega o
    # `token` da geração: todas as escritas no model são guardadas por ele (anti-supersede).
    class SubmitJob < ApplicationJob
      queue_as :medium

      INITIAL_POLL_WAIT = 5.seconds

      # params: { 'brief' =>, 'placeholders' => [], 'assets' => [], 'base_mjml' =>, 'brand' => { kit_id|import_id, mode } }
      # — com base_mjml é um ajuste (#1095)
      def perform(campaign_id, token, params)
        campaign = EmailCampaign.find_by(id: campaign_id)
        return if campaign.blank? || !active?(campaign, token)

        credential = Crm::Ai::CredentialResolver.new(account: campaign.account).resolve
        return fail_generation(campaign, token, 'ai_not_configured') if credential.blank?

        identity, brand_identity = resolve_identity(campaign, credential, params)
        generator = Generator.new(account: campaign.account, brief: params['brief'], placeholders: params['placeholders'],
                                  assets: params['assets'], base_mjml: params['base_mjml'], identity: identity)
        return fail_generation(campaign, token, 'base_mjml_too_large') if generator.base_mjml_too_large?
        return fail_generation(campaign, token, 'adjust_unreadable') if generator.adjust? && generator.sections.nil?

        req = generator.build
        if generator.adjust?
          start_adjustment(campaign, token, generator, req,
                           params.merge('brand_identity' => brand_identity, 'footer' => identity&.dig(:footer_mjml)))
        end
        client = Crm::Ai::ResponsesClient.new(credential: credential)
        result = client.create_background(
          model: Crm::Ai::Config::MODEL_EMAIL, instructions: req[:instructions], input: req[:input],
          schema: req[:schema], reasoning_effort: 'high', tools: req[:tools]
        )
        # Resposta sem id (provedor devolveu algo malformado): falha rápido em vez de esperar ~10min.
        return fail_generation(campaign, token, 'empty_response') if result[:id].blank?

        if campaign.ai_attach_response!(token, result[:id])
          options = { 'brand_identity' => brand_identity, 'placeholders' => Array(params['placeholders']) }
          PollJob.set(wait: INITIAL_POLL_WAIT).perform_later(campaign.id, token, result[:id], 0, options)
        else
          # Substituída no meio do caminho (token mudou): apaga a resposta órfã p/ não reter à toa.
          client.delete(result[:id])
        end
      rescue Crm::Ai::ResponsesClient::Error => e
        fail_generation(campaign, token, e.message)
      rescue StandardError => e
        Rails.logger.error("[EmailCampaigns::Ai::SubmitJob] campaign=#{campaign_id} #{e.class}: #{e.message}")
        fail_generation(campaign, token, 'generation_error')
      end

      private

      def active?(campaign, token)
        campaign.ai_processing? && campaign.ai_generation_token == token
      end

      # Ajuste (#1095): guarda o e-mail de antes e o pedido; o PollJob monta, confere e propõe o resultado. Com a
      # identidade usada (#1111: o aviso do site pedido no próprio pedido e o que "Aplicar" grava na campanha) e o rodapé
      # dela, que entra só se a IA vestir o e-mail todo com essa identidade (#1126).
      def start_adjustment(campaign, token, generator, req, params)
        Adjustment.start(campaign, token: token, request: { base: generator.sections.canonical, placeholders: params['placeholders'],
                                                            instructions: req[:instructions], input: req[:input_text],
                                                            brand_identity: params['brand_identity'], footer: params['footer'] })
      end

      # A site asked for in the request itself (#1111) wins over the identity chosen in the composer for this e-mail.
      def resolve_identity(campaign, credential, params)
        requested_url = SiteRequest.new(account: campaign.account, credential: credential, brief: params['brief']).url
        BrandResolution.new(campaign, params['brand'], requested_url: requested_url).call
      end

      # Só dispara o toast de falha se ESTA geração ainda era a ativa (ganhou o update guardado).
      def fail_generation(campaign, token, message)
        return if campaign.blank?

        Broadcaster.failed(campaign) if campaign.ai_fail!(token, message)
      end
    end
  end
end

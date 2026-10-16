# Envio de modelo pela conversa (#1703, #1705, épico #1320). O seletor da conversa já esconde os modelos que ela não
# consegue mandar (`inboxes/getConversationWhatsAppTemplates`), mas a mensagem também chega pela API e por modelo
# escolhido antes. Aqui o envio confere o formato pela regra única (`Whatsapp::Templates::SendableFormat`), com o que a própria
# mensagem traz em `processed_params`. Modelo de produto (topo PRODUCT, SPM, MPM, botão de catálogo, cartões de produto)
# sem os produtos e carrossel sem os cartões viram falha com o motivo na conversa, SEM chamar a Meta.
#
# #1705: cupom sem o código (1 a 15 letras), botão de link com o fim variável vazio (`url_suffix: true`) e oferta com
# contagem sem a validade, ou com ela já passada, também falham aqui: a tela da conversa pede os três
# (PreenchedorDoModelo) e o envio monta a oferta (`SendComponents`), mas a mensagem que chega sem eles iria à Meta para
# ser recusada. Os outros motivos da regra (código de verificação, pedido de
# ligação...) seguem o caminho de antes, porque quem chama pela API pode mandar o parâmetro que o Chatwoot já monta
# (ex.: `{ type: 'otp', parameter: }`). Os exemplos que front e back leem: spec/fixtures/whatsapp_templates/
# formatos_da_conversa.json.
#
# Prependido em `Whatsapp::SendOnWhatsappService` (do Chatwoot) pelo `config/initializers/whatsapp_templates.rb`: o
# arquivo do Chatwoot fica intacto. Confere antes de marcar o pedido de contato, para a recusa não deixar um pedido
# pendente. A campanha não passa por aqui (`OneoffCampaignService` confere no `DispatchCheck`); o envio fora da janela
# passa, com o mesmo `processed_params` que o `DispatchCheck` já liberou. Sem nome ou fora da lista da caixa, segue o
# caminho do Chatwoot, como antes.
module Whatsapp::Templates::ConversationSendGuard
  # Motivo do SendableFormat -> chave do texto (whatsapp_templates.errors.*).
  REFUSALS = {
    'catalog' => 'conversation_products', 'carousel' => 'conversation_carousel', 'copy_code' => 'conversation_coupon',
    'limited_time_offer' => 'conversation_offer_expiration', 'offer_expired' => 'conversation_offer_expired',
    'url_parameter' => 'conversation_url_parameter'
  }.freeze

  private

  def perform_reply
    reason = conversation_format_refusal unless broadcast_destination?
    return super unless reason

    Rails.logger.info("[whatsapp_templates][conversation_send] refused message=#{message.id} reason=#{reason}")
    message.update!(status: :failed, external_error: I18n.t("whatsapp_templates.errors.#{REFUSALS.fetch(reason)}"))
  end

  def conversation_format_refusal
    return if template_params.blank? || template_params['name'].blank?

    template = conversation_template
    return if template.blank?

    reason = Whatsapp::Templates::SendableFormat.check(template, recorded: template_params['processed_params'], url_suffix: true)
                                                .reason_code
    reason if REFUSALS.key?(reason)
  end

  # A mesma busca do `Whatsapp::TemplateProcessorService#find_template` (nome, idioma e aprovado). Lida aqui, sem
  # instanciar o processador: o pedido de contato recusado antes do envio não pode chegar a ele.
  def conversation_template
    language = template_params['language'].to_s.downcase
    Array(channel.message_templates).find do |template|
      template['name'] == template_params['name'] && template['language'].to_s.downcase == language &&
        template['status'].to_s.casecmp?('approved')
    end
  end
end

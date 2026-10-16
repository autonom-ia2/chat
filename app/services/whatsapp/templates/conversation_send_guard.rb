# Envio de modelo pela conversa (#1703, #1716, épico #1320). A mensagem chega pelo painel, pela API ou por modelo
# escolhido antes. Aqui o envio confere o formato pela regra única (`Whatsapp::Templates::SendableFormat`), com o que a
# própria mensagem traz em `processed_params`:
#   - modelo de produto (topo PRODUCT, SPM, MPM, botão de catálogo, cartões de produto) sem os produtos e carrossel sem
#     os cartões viram falha com o motivo na conversa, SEM chamar a Meta;
#   - com o pedido completo (#1716: os produtos escolhidos na conversa, ou os cartões com a foto), o envio é completado
#     pelos mesmos construtores da campanha (`Whatsapp::Templates::ConversationSend`): o catálogo relido (produto que
#     acabou não sai), o catálogo da WABA no pedido e o link assinado de cada foto. Produto só com a flag
#     `whatsapp_campaign_products`, como na campanha.
#
# Os outros motivos da regra (cupom, código de verificação, oferta, pedido de ligação...) seguem o caminho de antes,
# porque quem chama pela API pode mandar o parâmetro que o Chatwoot já monta (ex.: `{ type: 'otp', parameter: }`).
#
# Prependido em `Whatsapp::SendOnWhatsappService` (do Chatwoot) pelo `config/initializers/whatsapp_templates.rb`: o
# arquivo do Chatwoot fica intacto. Confere antes de marcar o pedido de contato, para a recusa não deixar um pedido
# pendente. O pedido completado vale só para este envio (`template_params`): a mensagem guarda o que a tela mandou, sem
# link assinado que expira. A campanha não passa por aqui (`OneoffCampaignService` confere no `DispatchCheck`); o envio
# fora da janela passa. Sem nome ou fora da lista da caixa, segue o caminho do Chatwoot, como antes.
module Whatsapp::Templates::ConversationSendGuard
  # Motivo do SendableFormat -> chave do texto (whatsapp_templates.errors.*).
  REFUSALS = { 'catalog' => 'conversation_products', 'carousel' => 'conversation_carousel' }.freeze

  private

  def perform_reply
    refusal = conversation_send_refusal unless broadcast_destination?
    return super unless refusal

    Rails.logger.info("[whatsapp_templates][conversation_send] refused message=#{message.id} reason=#{refusal[:key]}")
    message.update!(status: :failed, external_error: I18n.t("whatsapp_templates.errors.#{refusal[:key]}", **refusal[:args]))
  end

  # O pedido completado para este envio; sem ele, o que a mensagem guardou.
  def template_params
    @conversation_template_params || super
  end

  # { key:, args: } quando o envio não pode sair; nil quando segue.
  def conversation_send_refusal
    return if template_params.blank? || template_params['name'].blank?

    template = conversation_template
    return if template.blank?

    reason = Whatsapp::Templates::SendableFormat.check(template, recorded: template_params['processed_params']).reason_code
    return { key: REFUSALS.fetch(reason), args: {} } if REFUSALS.key?(reason)
    return if reason

    complete_conversation_send(template)
  end

  def complete_conversation_send(template)
    result = Whatsapp::Templates::ConversationSend.prepare(template: template, processed: template_params['processed_params'],
                                                           inbox: channel.inbox)
    return { key: result.error, args: { products: Array(result.details[:product_names]).join(', ') } } unless result.ok?

    @conversation_template_params = template_params.merge('processed_params' => result.processed) if result.processed
    nil
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

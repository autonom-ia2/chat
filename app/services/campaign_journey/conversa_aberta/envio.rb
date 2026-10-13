# O envio da conversa aberta (#1335). Prepend em Whatsapp::OneoffCampaignService (caminho Enterprise, com
# CampaignRecipient), por fora do CampaignJourney::WhatsappOneoffRecipients, em config/initializers/campaign_journey.rb.
#
# Na vez de cada pessoa, ANTES do modelo: se a campanha tem mensagem escrita, a flag da conta está ligada e a pessoa
# mandou mensagem para a caixa nas últimas 24 horas AGORA (Whatsapp::ServiceWindow, conferido de novo no envio), ela
# recebe a mensagem escrita, com os campos dela. Em qualquer outro caso recebe o modelo, como sempre:
# - fora da janela, sem a flag ou sem texto;
# - falta o valor de um campo (nunca vai texto pela metade);
# - a Meta recusa o texto na hora.
# Se a Meta recusar depois, pelo aviso de status 131047 (janela fechada), a CampaignJourney::ConversaAberta::Queda manda o
# modelo, uma vez só. A mensagem escrita entra na conversa com campaign_id (o robô do #1405 não assume).
module CampaignJourney::ConversaAberta::Envio
  PAUSADA = 'Campanha parada: o modelo não foi enviado depois do texto recusado'.freeze
  MODELO_NAO_PRONTO = 'O modelo não está pronto para envio: o texto foi recusado e o modelo não saiu'.freeze

  # A Queda pede o modelo para quem o texto não alcançou. Passa pelas mesmas travas do disparo
  # (CampaignPauses::WhatsappDispatchGate): campanha parada ou modelo que não confere não manda nada; a conferência
  # também liga o arquivo do topo do modelo (#1382).
  def enviar_modelo!(recipient)
    return recipient.mark_failed!(message: PAUSADA) if CampaignPause.open_for(campaign)
    return recipient.mark_failed!(message: MODELO_NAO_PRONTO) if template_check_applies? && !template_verdict.ok?

    modelo_forcado << recipient.id
    process_recipient(recipient)
  end

  private

  def send_whatsapp_template_message(recipient:, to:, template_params:)
    texto = modelo_forcado.exclude?(recipient.id) && texto_para(recipient.contact)
    return super unless texto

    source_id = channel.provider_service.send_message(to, CampaignJourney::ConversaAberta::TextoDeEnvio.new(texto))
    return super if source_id.blank?

    # A Meta aceitou: a pessoa fica `sent` ANTES de qualquer outra gravação (nunca vira `failed` depois do aceite).
    update_recipient_from_provider_response(recipient, source_id)
    registrar_texto(recipient, to, texto, source_id)
  end

  # Depois do aceite: o texto que a pessoa recebeu, a linha da entrega (para a queda no 131047) e a mensagem na
  # conversa. Uma falha aqui só vai ao log: a mensagem já saiu.
  def registrar_texto(recipient, destination, texto, source_id)
    recipient.update!(message_content: texto)
    CampaignFreeTextDelivery.create!(account_id: campaign.account_id, campaign: campaign, campaign_recipient_id: recipient.id,
                                     inbox_id: inbox.id, source_id: source_id)
    CampaignJourney::SentMessageRecorder.new(campaign: campaign, recipient: recipient.reload, free_text: true).record_at_send(destination)
  rescue StandardError => e
    Rails.logger.error "[ConversaAberta] campaign=#{campaign.id} recipient=#{recipient.id} texto enviado, registro falhou: #{e.class}"
  end

  # O texto pronto da pessoa, ou nil quando vai o modelo (inclusive se algo falhar ao montar o texto).
  def texto_para(contact)
    return unless texto_da_campanha && Whatsapp::ServiceWindow.new(inbox: inbox).open?(contact)

    import = audience_link.campaign_import
    resolver = TemplateFields::Resolver.for_audience(
      contact: contact, columns: import.extra_columns, values: audience_extra_values(contact.id),
      types: CampaignImports::ColumnTypes.stored(import)
    )
    CampaignJourney::ConversaAberta::Texto.preencher(texto_da_campanha, resolver,
                                                     colunas: CampaignJourney::ConversaAberta::Texto.colunas(import.extra_columns))
  rescue StandardError => e
    Rails.logger.error "[ConversaAberta] campaign=#{campaign.id} contact=#{contact.id} texto não montado, vai o modelo: #{e.class}"
    nil
  end

  def texto_da_campanha
    return @texto_da_campanha if defined?(@texto_da_campanha)

    @texto_da_campanha = audience_link&.campaign_import && CampaignJourney::ConversaAberta.enabled?(campaign.account) &&
                         CampaignFreeText.find_by(campaign_id: campaign.id)&.content
  end

  def modelo_forcado
    @modelo_forcado ||= Set.new
  end
end

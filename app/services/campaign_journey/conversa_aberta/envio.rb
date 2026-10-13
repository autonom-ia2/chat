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
  # A Queda pede o modelo para quem o texto não alcançou.
  def enviar_modelo!(recipient)
    modelo_forcado << recipient.id
    process_recipient(recipient)
  end

  private

  def send_whatsapp_template_message(recipient:, to:, template_params:)
    texto = modelo_forcado.exclude?(recipient.id) && texto_para(recipient.contact)
    return super unless texto

    source_id = channel.provider_service.send_message(to, CampaignJourney::ConversaAberta::TextoDeEnvio.new(texto))
    return super if source_id.blank?

    entregar_texto(recipient, to, texto, source_id)
  end

  def entregar_texto(recipient, destination, texto, source_id)
    recipient.update!(message_content: texto)
    CampaignFreeTextDelivery.create!(account_id: campaign.account_id, campaign: campaign, campaign_recipient_id: recipient.id,
                                     inbox_id: inbox.id, source_id: source_id)
    update_recipient_from_provider_response(recipient, source_id)
    CampaignJourney::SentMessageRecorder.new(campaign: campaign, recipient: recipient.reload, free_text: true).record_at_send(destination)
  end

  # O texto pronto da pessoa, ou nil quando vai o modelo.
  def texto_para(contact)
    return unless texto_da_campanha && Whatsapp::ServiceWindow.new(inbox: inbox).open?(contact)

    import = audience_link.campaign_import
    resolver = TemplateFields::Resolver.for_audience(
      contact: contact, columns: import.extra_columns, values: audience_extra_values(contact.id),
      types: CampaignImports::ColumnTypes.stored(import)
    )
    CampaignJourney::ConversaAberta::Texto.preencher(texto_da_campanha, resolver,
                                                     colunas: CampaignJourney::ConversaAberta::Texto.colunas(import.extra_columns))
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

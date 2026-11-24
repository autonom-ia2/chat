# #3099 (D2): no e-mail, a versão 2 muda só o assunto. O motor de e-mail monta o assunto da campanha para todos
# (EmailCampaigns::DeliveryEngine e EmailCampaigns::DirectInbox::RecipientSender, #render); este módulo, prepend nos dois
# por config/initializers/campaign_journey.rb, troca o assunto de quem caiu na versão 2 pelo assunto dela, com os mesmos
# campos da pessoa. Corpo, rastreio e descadastro seguem iguais. Campanha sem duas versões: o motor de sempre.
module CampaignJourney::DuasVersoes::AssuntoDoEmail
  private

  def render(recipient)
    rendered = super
    assunto = assunto_da_versao_2(recipient)
    assunto ? rendered.merge(subject: EmailCampaigns::TemplateRenderer.new(recipient).render(assunto)) : rendered
  end

  def assunto_da_versao_2(recipient)
    duas_versoes = @duas_versoes_do_email ||= CampaignJourney::DuasVersoes.para(@campaign)
    return unless recipient.contact_id && duas_versoes.versao_2?(recipient.contact_id)

    duas_versoes.segunda['subject'].presence
  end
end

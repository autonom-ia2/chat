# frozen_string_literal: true

# Lista de e-mail da campanha de e-mail (G52, #2760). Liga os módulos do fork sem editar os arquivos do upstream, como
# o config/initializers/campaign_journey.rb.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  EmailCampaign.include(EmailLists::CampaignList) unless EmailCampaign.include?(EmailLists::CampaignList)
  # Apagar a etiqueta apaga a lista pelo Rails (e a lista solta as campanhas antes).
  Label.include(EmailLists::LabelList) unless Label.include?(EmailLists::LabelList)
  # Público salvo e lista nunca juntos, dos dois lados.
  CampaignAudienceLink.include(EmailLists::AudienceLinkGuard) unless CampaignAudienceLink.include?(EmailLists::AudienceLinkGuard)
  # Agendar, mandar agora e o agendador montam a lista na hora do envio.
  prepend_once.call(EmailCampaign, EmailLists::Gate::Campaign)
  prepend_once.call(EmailCampaigns::Scheduler, EmailLists::Gate::Scheduler)
  prepend_once.call(EmailCampaigns::Presentation::SendReadiness, EmailLists::Gate::Readiness)
  # A campanha com lista não aceita planilha.
  prepend_once.call(Api::V1::Accounts::EmailCampaigns::RecipientsController, EmailLists::RecipientsGuard)
end

# Público salvo e lista de e-mail nunca juntos na mesma campanha de e-mail (G52, #2760). O outro lado é a validação
# da campanha (EmailLists::CampaignList#email_list_sem_publico_nem_planilha). Incluído no CampaignAudienceLink por
# config/initializers/email_lists.rb, sem mexer no modelo do upstream.
module EmailLists::AudienceLinkGuard
  extend ActiveSupport::Concern

  included do
    validate :campanha_sem_lista_de_email
  end

  private

  def campanha_sem_lista_de_email
    return unless campaign.is_a?(EmailCampaign) && campaign.email_list_id.present?

    errors.add(:campaign, 'email_list_linked')
  end
end

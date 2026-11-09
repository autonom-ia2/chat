# A lista de e-mail da campanha de e-mail (G52, #2760). Incluído no EmailCampaign por
# config/initializers/email_lists.rb, sem mexer no modelo do upstream.
#
# A lista é o público inteiro: a campanha com lista não aceita planilha (EmailLists::RecipientsGuard) nem vem de um
# público salvo da jornada, e não troca de lista com uma importação de planilha em andamento. Escolher, trocar ou tirar
# a lista no rascunho já monta os destinatários (EmailLists::Recipients); o envio monta de novo, com quem estiver na
# lista naquela hora.
module EmailLists::CampaignList
  extend ActiveSupport::Concern

  included do
    belongs_to :email_list, optional: true, inverse_of: :email_campaigns

    validate :email_list_da_mesma_conta, if: :email_list_id_changed?
    validate :email_list_sem_publico_nem_planilha, if: -> { email_list_id_changed? && email_list_id.present? }
    # Depois do commit, para tomar a trava de envio na ordem de sempre (conta antes da campanha) em vez de pedi-la com a
    # linha da campanha já presa pelo UPDATE.
    after_commit :sincronizar_email_list, on: %i[create update], if: :saved_change_to_email_list_id?
  end

  private

  def email_list_da_mesma_conta
    return if email_list.nil? || email_list.account_id == account_id

    errors.add(:email_list_id, 'must belong to the same account')
  end

  def email_list_sem_publico_nem_planilha
    errors.add(:email_list_id, 'audience_linked') if persisted? && CampaignAudienceLink.for_campaign(self)
    errors.add(:email_list_id, 'import_in_progress') if persisted? && recipient_import_active?
  end

  # O estado vale o do banco, relido sob a trava (`with_lock` recarrega a campanha): o objeto em memória pode estar
  # velho, e a campanha que outro processo já mandou não perde os destinatários.
  def sincronizar_email_list
    with_delivery_lock { EmailLists::Recipients.new(self).sync! if draft? || scheduled? }
  end
end

# #1898: depois do disparo, o rascunho da "Nova campanha" sai da lista de prontas para disparar.
# - Oficial, SMS e API: o POST de campaign_journey/campaigns traz o `draft_id` do rascunho de onde veio, e só aquele
#   rascunho da conta sai (id único; lista ou objeto é ignorado). Sair depois do disparo não é "apagar": vale para
#   quem disparou, seja ou não o autor.
# - E-mail: o POST da jornada só cria o rascunho de e-mail; o `draft_id` fica ligado a ele (link_email). Quem tira o
#   rascunho da lista é o send_now/schedule daquela campanha de e-mail.
# Roda depois do envio, fora da transação dele (os criadores enfileiram jobs). Falha vira log e não desfaz o disparo:
# o pior caso é o rascunho continuar na lista, e no e-mail o CampaignJourneyDraft.pending já o esconde.
module CampaignJourney::DraftCleanup
  module_function

  def after_dispatch(account, draft_id: nil, email_campaign: nil)
    drafts = CampaignJourneyDraft.where(account_id: account.id)
    if email_campaign
      drafts.where(email_campaign_id: email_campaign.id).delete_all
    elsif (id = single_id(draft_id))
      drafts.where(id: id).delete_all
    end
  rescue StandardError => e
    Rails.logger.warn("[campaign_journey][draft_cleanup] account=#{account.id} #{e.class}")
  end

  def link_email(account, draft_id:, email_campaign:)
    id = single_id(draft_id)
    return if id.nil?

    CampaignJourneyDraft.where(account_id: account.id, id: id).update_all(email_campaign_id: email_campaign.id, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[campaign_journey][draft_cleanup] link account=#{account.id} #{e.class}")
  end

  # Só um id inteiro: lista, objeto ou texto que não é número não apaga nada.
  def single_id(value)
    return unless value.is_a?(String) || value.is_a?(Integer)

    Integer(value.to_s, exception: false)&.then { |id| id.positive? ? id : nil }
  end
end

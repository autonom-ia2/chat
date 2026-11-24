# #3063 (item 2): the account's limit per customer and sending hours (Autonomia::RitmoDeEnvio::Porteiro) on e-mail
# campaigns, for both engines (SES and the direct inbox). Out of them, the recipient keeps `pending` with `adiado_ate`
# and is not picked until then; the campaign stays `sending` (EmailCampaign#finalize! waits for every pending) and
# Autonomia::RitmoDeEnvio::Varredura enqueues the DeliveryJob again when the time comes.
#
# The person is the recipient's contact or, for a spreadsheet recipient without one, the contact of the account with
# that e-mail (the same match the refusal check uses). Nobody with that e-mail: only the sending hours apply, in the
# account's time zone, and the e-mail does not count for the limit.
module EmailCampaigns::RitmoDoDestinatario
  ORIGEM = 'campanha_email'.freeze

  module_function

  # #3099: com as duas versões, enquanto o resto espera a escolha, só quem caiu no teste (o resto fica `pending`, e a
  # campanha `sending`, até CampaignJourney::DuasVersoes#mandar_resto!).
  def pendentes_na_vez(campaign, agora: Time.current)
    pendentes = campaign.email_campaign_recipients.pending.where('adiado_ate IS NULL OR adiado_ate <= ?', agora)
    CampaignJourney::DuasVersoes.para(campaign).so_quem_recebe_agora(pendentes, coluna: :contact_id)
  end

  # `contato`: o de #contato, buscado uma vez por destinatário pelo motor e passado aos dois.
  def adiado?(campaign, recipient, contato)
    ate = Autonomia::RitmoDeEnvio::Porteiro.quando(account: campaign.account, contact: contato)
    return false unless ate

    recipient.update_columns(adiado_ate: ate, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    true
  end

  def contar!(campaign, contato)
    Autonomia::RitmoDeEnvio::Porteiro.contar!(account: campaign.account, contact_id: contato&.id, origem: ORIGEM)
  end

  def contato(campaign, recipient)
    return recipient.contact if recipient.contact_id.present?

    campaign.account.contacts.where('lower(email) = ?', recipient.email.to_s.strip.downcase).order(:id).first
  end
end

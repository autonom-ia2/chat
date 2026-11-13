# "Trazer minha lista" (#2896): das pessoas que a conta já tinha, quais foram procuradas desde que a lista chegou: têm
# conversa aberta de lá para cá, ou entraram numa campanha de lá para cá (WhatsApp ou SMS, e-mail, WhatsApp Oficial).
#
# O "Desfazer" não tira o telefone nem o e-mail que a lista pôs nessas pessoas: a conta já falou com elas por ali, e
# esvaziar o campo deixaria a conversa sem o contato de quem está do outro lado. Os outros campos voltam como sempre.
class Relacionamentos::Trazer::QuemFoiProcurado
  def initialize(conta_id, desde:)
    @conta_id = conta_id
    @desde = desde
  end

  # ids: pessoas da conta. Devolve o conjunto das que foram procuradas.
  def entre(ids)
    return Set.new if ids.empty?

    onde_aparece.flat_map { |registros| registros.where(contact_id: ids, created_at: @desde..).distinct.pluck(:contact_id) }.to_set
  end

  def procurada?(id)
    entre([id]).any?
  end

  private

  def onde_aparece
    da_conta = { account_id: @conta_id }
    [Conversation.where(da_conta), CampaignRecipient.where(da_conta),
     EmailCampaignRecipient.where(email_campaign_id: EmailCampaign.where(da_conta).select(:id)),
     WhatsappApiCampaignRecipient.where(da_conta)]
  end
end

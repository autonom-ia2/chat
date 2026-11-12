# "Trazer minha lista" (#2896): das pessoas que uma lista criou, quais o "Desfazer" não apaga. A lista só leva embora
# quem ela trouxe e em quem ninguém tocou. Fica quem:
#
# - tem conversa;
# - tem card no funil, como a pessoa do card ou como quem pediu (solicitante);
# - tem nota escrita na ficha ou retorno marcado (os dois saem junto com a pessoa, e foi alguém que os pôs lá);
# - recebeu, ou está na fila de, uma campanha (WhatsApp ou SMS, e-mail, WhatsApp Oficial);
# - está em outra importação: outra lista trazida, um Público ou uma base de campanha;
# - entrou num Público montado pelas conversas;
# - recusou mensagens (opted_out_at) ou está bloqueada. Apagar a pessoa apagaria a recusa junto, e a próxima pessoa
#   criada com o mesmo telefone voltaria a receber campanha.
#
# Quem já não existe (apagada à mão, ou mesclada em outra pessoa) não sai nem fica: é pulada.
#
# A prévia e o Desfazer leem por aqui, em blocos, então o que a prévia promete é o que o Desfazer faz.
class Relacionamentos::Trazer::QuemFica
  BLOCO = 500

  def initialize(importacao)
    @importacao = importacao
    @conta = importacao.account
  end

  # Bloco a bloco, das pessoas que a lista criou e que ainda existem: os ids das que saem e os das que ficam.
  def em_blocos
    criadas.in_batches(of: BLOCO) do |linhas|
      existem = @conta.contacts.where(id: linhas.select(:contact_id)).ids
      ficam = entre(existem)
      yield existem.reject { |id| ficam.include?(id) }, ficam.to_a
    end
  end

  # As linhas das pessoas que a lista criou.
  def criadas
    @importacao.campaign_import_rows.status_imported.where(was_existing_contact: false).where.not(contact_id: nil)
  end

  # ids: pessoas da conta. Devolve o conjunto das que ficam.
  def entre(ids)
    return Set.new if ids.empty?

    onde_aparece.flat_map { |registros, coluna| registros.where(coluna => ids).distinct.pluck(coluna) }.to_set
  end

  private

  # [de onde, coluna com o id da pessoa]
  def onde_aparece
    da_conta = { account_id: @conta.id }
    [
      [Conversation.where(da_conta), :contact_id],
      [Crm::Card.where(da_conta), :contact_id], [Crm::Card.where(da_conta), :solicitante_contact_id],
      [Note.where(da_conta), :contact_id], [Crm::FollowUp.where(da_conta), :contact_id], [Crm::FollowUpSeries.where(da_conta), :contact_id],
      [CampaignRecipient.where(da_conta), :contact_id], [EmailCampaignRecipient.all, :contact_id],
      [WhatsappApiCampaignRecipient.where(da_conta), :contact_id],
      [CampaignImportRow.where.not(campaign_import_id: @importacao.id), :contact_id],
      [ConversationAudiencePerson.all, :contact_id],
      [@conta.contacts.where.not(opted_out_at: nil).or(@conta.contacts.where(blocked: true)), :id]
    ]
  end
end

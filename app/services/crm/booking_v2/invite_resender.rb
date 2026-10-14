# "Enviar de novo" da lista "abriram e não marcaram" (#1194, J7-A4). Só roda quando a pessoa toca no botão: nada
# sai sozinho. Reaproveita o link por cliente (F1-C) em nome de quem o criou: `InviteCreator` devolve o link ativo
# desse autor para o cliente (ou cria um novo, na mesma página e com o mesmo responsável, se o antigo venceu) e
# `InviteDeliverer` o manda na conversa como a pessoa que tocou, com o texto pronto. Assim, quem vê a equipe e
# reenvia o link de um colega não cria um segundo link ativo para o cliente nem troca quem atende; e o envio
# continua nos números do autor. Autor que saiu da conta ou já não atende: o link novo fica em nome de quem tocou.
# Tudo numa transação: se o envio for recusado, nenhum link novo fica para trás.
#
# Quem chama já confirmou que a pessoa vê o convite (lista) e a conversa (`ConversationPolicy#show?`); o card só
# vai junto se ela o vê. Recusas (InviteError): 'no_conversation' (sem conversa para mandar), 'cannot_reply' (a
# janela de mensagens está fechada: o cliente precisa escrever primeiro), e as do link por cliente ('no_page',
# 'invite_invalid').
class Crm::BookingV2::InviteResender
  def initialize(invite:, user:, conversation:, card: nil)
    @invite = invite
    @user = user
    @conversation = conversation
    @card = card
  end

  def perform
    raise Crm::BookingV2::InviteError, 'no_conversation' if conversation.blank?
    raise Crm::BookingV2::InviteError, 'cannot_reply' unless conversation.can_reply?

    ActiveRecord::Base.transaction do
      fresh = Crm::BookingV2::InviteCreator.new(
        account: invite.account, user: author, page_id: invite.booking_profile_id,
        client: { card: card, conversation: conversation }
      ).perform
      Crm::BookingV2::InviteDeliverer.new(invite: fresh, user: user, conversation: conversation).perform
      fresh.reload
    end
  end

  private

  attr_reader :invite, :user, :conversation, :card

  def author
    owner = invite.created_by
    return user if owner.blank? || owner == user

    Crm::BookingV2::HostEligibility.eligible?(account: invite.account, user: owner) ? owner : user
  end
end

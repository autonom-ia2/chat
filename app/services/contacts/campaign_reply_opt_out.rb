# A recusa 'campaign_reply' (#1449) vale pelo número, não só pelo registro do contato (decisão do Rodrigo, 14/10/2026).
#
# Ao marcar, o contato guarda o número em que a pessoa pediu para parar (additional_attributes.campaign_reply_phone).
# Esse contato é a prova da recusa do número: outro contato da conta que nasce com esse telefone, ou que passa a tê-lo,
# herda a recusa (Contacts::OptOutInheritance), mesmo que o original tenha trocado de número depois. Contato que só
# herdou não guarda número e não serve de prova.
#
# Desfazer no painel (OptOutsController) desfaz o número inteiro: tira a prova de todos os originais e depois a recusa
# de cada contato com aquela origem e aquele número. Se outra origem ainda vale para algum deles (e-mail descadastrado,
# lead recusado), a recusa fica com ela (ContactOptOut#release_opt_out!).
#
# Limites conhecidos: o número gravado fica em additional_attributes, que a API do contato também edita, e na fusão de
# dois originais de números diferentes fica o do contato que permanece; um contato que só herdou e depois troca de
# telefone continua recusado até alguém desfazer nele; e se o contato já tinha recusado por outra origem quando o pedido
# chegou, o número não é gravado.
module Contacts::CampaignReplyOptOut
  SOURCE = 'campaign_reply'.freeze
  PHONE_KEY = 'campaign_reply_phone'.freeze

  module_function

  # Retorna true quando gravou a recusa (contato que já tinha recusado fica como está).
  def mark!(contact)
    Contact.transaction do
      next false unless contact.opt_out!(source: SOURCE)

      record_number(contact) if contact.phone_number.present?
      true
    end
  end

  # Algum outro contato da conta pediu para parar neste número e a recusa dele ainda é desta origem.
  def number_marked?(contact)
    return false if contact.phone_number.blank?

    marked_with(contact.account_id, [contact.phone_number]).where.not(id: contact.id).exists?
  end

  # Os contatos do grupo são travados na ordem do id, numa transação só, para dois "desfazer" ao mesmo tempo não se
  # travarem em ordens diferentes.
  def release_number!(contact, by:)
    Contact.transaction do
      group = number_group(contact).order(:id).lock.to_a
      # Dois laços de propósito: com a prova de algum original ainda de pé, release_opt_out! dos outros não solta nada.
      group.each { |member| forget_number(member) }
      group.each { |member| member.release_opt_out!(source: SOURCE, by: by) } # rubocop:disable Style/CombinableLoops
    end
    contact.reload
  end

  # O número do pedido é o gravado no original; no contato que só herdou, é o telefone atual. O grupo é o próprio
  # contato, os originais daquele número e os que só herdaram (sem número gravado) e estão nele. Original de outro
  # número, mesmo que hoje esteja neste telefone, fica de fora: o pedido dele é de outro número.
  def number_group(contact)
    number = contact.additional_attributes.to_h[PHONE_KEY].presence || contact.phone_number
    scope = with_source(contact.account_id)
    group = scope.where(id: contact.id)
    return group if number.blank?

    heirs = scope.where(phone_number: number).where("contacts.additional_attributes ->> '#{PHONE_KEY}' IS NULL")
    group.or(marked_with(contact.account_id, [number])).or(heirs)
  end

  def with_source(account_id)
    Contact.opted_out.where(account_id: account_id, opt_out_source: SOURCE)
  end

  def marked_with(account_id, numbers)
    with_source(account_id).where("contacts.additional_attributes ->> '#{PHONE_KEY}' IN (?)", numbers)
  end

  def record_number(contact)
    contact.additional_attributes = contact.additional_attributes.to_h.merge(PHONE_KEY => contact.phone_number)
    contact.save!(validate: false)
  end

  def forget_number(contact)
    return unless contact.additional_attributes.to_h.key?(PHONE_KEY)

    contact.additional_attributes = contact.additional_attributes.to_h.except(PHONE_KEY)
    contact.save!(validate: false)
  end
end

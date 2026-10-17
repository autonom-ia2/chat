# Mensagem apagada (#1601; decisão N3 do Rodrigo: só o mínimo). A mensagem apagada (pela equipe ou retirada pelo
# cliente) invalida o fato que dependia SÓ dela: a versão expira e o trecho copiado sai. O fato com outra prova continua.
module Crm::Memoria::Recalcular
  module_function

  def apagada?(message)
    atributos = message.content_attributes.to_h
    atributos['deleted'].present? || atributos['deleted_by_contact_at'].present?
  end

  def mensagem_apagada!(message)
    Crm::MemoriaFato.vivos.where(account_id: message.account_id).where('prova_message_ids @> ARRAY[?]::bigint[]', message.id)
                    .find_each do |fato|
      next unless fato.prova_message_ids == [message.id]

      fato.update!(expirado_em: Time.current, prova_trecho: nil)
    end
  end
end

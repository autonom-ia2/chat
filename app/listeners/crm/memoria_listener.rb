# Memória das IAs (#1601): o listener mínimo. Só a mensagem que mudou de um jeito que mexe num fato:
# - apagada (pela equipe, `deleted`, ou retirada pelo cliente, `deleted_by_contact_at`): o fato que dependia só dela
#   deixa de valer;
# - EDITADA pelo cliente (o texto mudou; o #1702b e o #1709 gravam `edited_at`/`edit_history`): o fato que ela provava
#   é conferido de novo contra o texto novo, e o card é reavaliado de carona (decisão do Rodrigo, 17/10, opção A).
# Não abre turno da IA. Só confere a flag e enfileira.
class Crm::MemoriaListener < BaseListener
  def message_updated(event)
    message = event.data[:message]
    evento = Crm::Memoria::Recalcular.evento(message, event.data[:previous_changes])
    return if evento.nil? || !Crm::Memoria.ativa?(message.conversation)

    Crm::Memoria::MensagemJob.perform_later(message.id, evento)
  end
end

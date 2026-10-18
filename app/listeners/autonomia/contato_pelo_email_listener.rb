# Contato pelo e-mail recebido (#1813): o gancho no fluxo do Chatwoot. Só confere e enfileira; a IA roda no job.
class Autonomia::ContatoPeloEmailListener < BaseListener
  def message_created(event)
    message = event.data[:message]
    return unless Autonomia::ContatoPeloEmail.email_do_cliente?(message) && Autonomia::ContatoPeloEmail.ligado?(message.account)

    Autonomia::ContatoPeloEmailJob.perform_later(message.id)
  end
end

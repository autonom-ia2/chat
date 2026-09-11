# O VIGIA DO ENVIO AO CANAL (rodada 7 da entrega 11, P2 do Codex).
#
# A mensagem que o publicador cria só chega ao cliente quando o `send_reply` da `Message`
# (`after_create_commit`) enfileira o `SendReplyJob`. Esse callback é o QUINTO de
# `execute_after_create_commit_callbacks`; o quarto (`dispatch_create_events`) fala com o Redis e pode
# levantar — e aí a mensagem está no banco, o token está publicado, e NADA foi enviado. Quem reconcilia
# precisa saber se o envio foi disparado, e nem a mensagem nem o job deixam marca durável disso antes
# de o envio acontecer (`source_id` só existe DEPOIS de o canal responder). O que existe é o
# instrumento do ActiveJob: todo `enqueue` emite `enqueue.active_job` (ou `enqueue_at.active_job`,
# o do `set(wait:)`) com o job, e o job diz se entrou na fila (`successfully_enqueued?` — falso quando
# o adapter levantou ou um callback de enqueue barrou). O vigia escuta durante a publicação e anota
# o id da mensagem de cada `SendReplyJob` que ENTROU.
#
# A assinatura é do processo (todas as threads), pelo tempo do bloco; o que outras threads do Sidekiq
# enfileiram cai na mesma lista e é inofensivo: a pergunta é sempre por UMA mensagem, a desta
# publicação. Anotar é escrita sob mutex, porque essas threads enfileiram ao mesmo tempo.
#
# RESSALVA (rodada 8): o vigia anota o que ENTROU segundo o adapter. Se o Redis aceita o job e perde a
# resposta na mesma chamada, o adapter levanta, `successfully_enqueued?` fica falso e o job que entrou
# não é anotado — e a recuperação do publicador põe um segundo (ver `AsyncPublisher#reenviar`).
class Autonomia::Agents::Tools::VigiaDeEnvio
  EVENTOS = /\A(enqueue|enqueue_at)\.active_job\z/

  def initialize
    @ids = []
    @mutex = Mutex.new
  end

  # Executa o bloco escutando os enfileiramentos; devolve o que o bloco devolver.
  def observar(&)
    ActiveSupport::Notifications.subscribed(method(:anotar), EVENTOS, &)
  end

  # O `SendReplyJob` desta mensagem entrou na fila enquanto o bloco rodava?
  def enfileirou?(message_id)
    @mutex.synchronize { @ids.include?(message_id) }
  end

  private

  def anotar(_nome, _inicio, _fim, _id, payload)
    job = payload[:job]
    return unless job.is_a?(::SendReplyJob) && job.successfully_enqueued? && payload[:exception_object].nil?

    @mutex.synchronize { @ids << job.arguments.first }
  end
end

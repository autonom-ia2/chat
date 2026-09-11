# A FILA QUE RECUSA O `SendReplyJob` (rodadas 7–9 da entrega 11). É como se simula "o Redis está fora
# só para o envio ao canal": o `send_reply` da `Message` E a recuperação do publicador levantam, e todo
# outro job (`PurgeJob`, `AsyncPublishJob`) entra normalmente. Compartilhado pelos specs do publicador,
# da retomada e do varredor — a pré-condição dos três é a mesma mensagem marcada com pendência.
module FilaDeEnvioHelper
  def fila_recusa_o_envio
    fila = ActiveJob::Base.queue_adapter
    %i[enqueue enqueue_at].each do |metodo|
      allow(fila).to receive(metodo).and_wrap_original do |original, job, *resto|
        raise Redis::CannotConnectError, 'redis fora' if job.is_a?(SendReplyJob)

        original.call(job, *resto)
      end
    end
  end

  def fila_volta
    fila = ActiveJob::Base.queue_adapter
    %i[enqueue enqueue_at].each { |metodo| allow(fila).to receive(metodo).and_call_original }
  end
end

RSpec.configure do |config|
  config.include FilaDeEnvioHelper
end

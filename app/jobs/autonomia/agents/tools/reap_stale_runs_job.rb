# VARREDOR das execuções assíncronas que ficaram penduradas (#313).
#
# Uma execução avança porque um job se re-agenda. Se essa corrente se rompe — o worker morreu entre
# o aceite e o despacho (um deploy basta: o Sidekiq desta instalação tem `:timeout: 25`), ou o
# `perform_later` falhou porque o Redis estava fora — a linha fica viva para sempre: nunca
# finalizada, nunca recolhida, e o cliente esperando uma cotação que ninguém vai fazer.
#
# Este job é o único ponto que enxerga isso. Ele NÃO retoma a execução: retomar significaria cotar
# de novo no portal, e não há como saber o que já aconteceu lá. Ele fecha a linha e avisa o cliente
# uma vez, com a frase da própria ferramenta — melhor uma resposta honesta do que silêncio.
#
# E é também o único ponto periódico que existe para duas pontas soltas da entrega de arquivo
# (entrega 11): o blob que ficou sem dono (`recolher_blobs_sem_dono`, rodada 7) e a mensagem publicada
# cujo envio ao canal nunca entrou na fila (`retomar_envios_pendentes`, rodada 9).
class Autonomia::Agents::Tools::ReapStaleRunsJob < ApplicationJob
  queue_as :scheduled_jobs

  BATCH_LIMIT = 500
  # Folga sobre o prazo da execução: só recolhe o que já passou do `expires_at` com margem, para
  # nunca competir com um poll legítimo que está prestes a rodar.
  GRACE = 5.minutes
  # Uma execução `pending` que nunca foi promovida não tem `expires_at`. Cai por idade.
  PENDING_MAX_AGE = 1.hour
  # O blob da entrega de arquivo (entrega 11) é gravado ANTES da mensagem; a idade é a margem que
  # protege um upload em andamento (a linha existe antes do anexo) — a transferência inteira cabe em
  # segundos, e uma hora é folga, não medida.
  BLOB_SEM_DONO_IDADE = 1.hour
  # A pendência de envio (rodada 9) é procurada nas mensagens dos últimos dois dias: a marca nasce
  # segundos depois da mensagem, e o varredor passa a cada 10 min — dois dias é folga para um Redis
  # que ficou fora um fim de semana, e é o que mantém a leitura pelo índice de `created_at` curta.
  ENVIO_PENDENTE_JANELA = 2.days
  ENVIO_PENDENTE_LIMITE = 200

  def perform
    reap_running
    reap_pending
    recolher_blobs_sem_dono
    retomar_envios_pendentes
  end

  private

  # A MENSAGEM COM ENVIO PENDENTE (rodada 9 da entrega 11, P2 do Codex): o publicador a deixou no banco
  # com a marca porque o `SendReplyJob` não entrou na fila, e ninguém a reemite — o `AsyncRunJob`
  # encerra, `comparativo_enviado` impede nova emissão do PDF, o Redis voltar não dispara nada. Este é
  # o recuperador DURÁVEL: para cada marcada, a `RetomadaDeEnvio` da execução que a publicou trava a
  # conversa, relê a mensagem, reconfere a autorização e reenfileira (ou abandona, com motivo). A marca
  # sem execução (ou de execução apagada) é abandonada aqui: não há autorização que a valide.
  def retomar_envios_pendentes
    ::Autonomia::Agents::Tools::PendenciaDeEnvio
      .marcadas(desde: ENVIO_PENDENTE_JANELA.ago, limite: ENVIO_PENDENTE_LIMITE)
      .each { |mensagem| retomar_envio(mensagem) }
  end

  def retomar_envio(mensagem)
    pendencia = ::Autonomia::Agents::Tools::PendenciaDeEnvio
    run = ::Autonomia::Agents::ToolRun.find_by(id: pendencia.execucao_id(mensagem))
    return pendencia.abandonar(mensagem, motivo: 'sem_execucao', contexto: 'varredor') if run.nil?

    ::Autonomia::Agents::Tools::RetomadaDeEnvio.new(run: run).recuperar(mensagem)
  rescue StandardError => e
    # Uma mensagem não derruba as outras: registrada, e o varredor segue; a marca fica para a próxima.
    Rails.logger.warn("[autonomia][tool][async] retomada de envio falhou varredor message=#{mensagem.id} #{e.class}")
  end

  # O BLOB QUE FICOU SEM DONO (rodada 7 da entrega 11): o publicador grava o blob, e só depois cria a
  # mensagem que o anexa; se o processo morre entre uma coisa e a outra, nem o `ensure` do publicador
  # roda, e a linha (com o arquivo já no armazenamento, ou sem ele) fica para sempre. Este é o único
  # ponto periódico que existe para reconhecê-la — pela MARCA que a entrega põe no `metadata` — e
  # apagá-la em segundo plano, como qualquer blob sem dono do publicador. Nada sem a marca é tocado.
  def recolher_blobs_sem_dono
    ::Autonomia::Agents::Tools::EntregaDeArquivo
      .blobs_sem_dono(antes_de: BLOB_SEM_DONO_IDADE.ago, limite: BATCH_LIMIT)
      .each { |blob| ::Autonomia::Agents::Tools::EntregaDeArquivo.agendar_limpeza(blob, contexto: 'varredor') }
  end

  def reap_running
    ::Autonomia::Agents::ToolRun.where(status: 'running')
                                .where(expires_at: ...GRACE.ago)
                                .limit(BATCH_LIMIT).each { |run| close(run) }
  end

  # `pending` nunca falou com o portal e nunca prometeu nada ao cliente: descarta em silêncio.
  def reap_pending
    ::Autonomia::Agents::ToolRun.where(status: 'pending')
                                .where(created_at: ...PENDING_MAX_AGE.ago)
                                .limit(BATCH_LIMIT).each(&:discard!)
  end

  # Se a execução morreu com a INTENÇÃO anotada e sem o número (entrega 5), a cotação pode existir
  # no portal sem registro nosso: o `finish!` a marca como possivelmente duplicada, para o corretor
  # achar, e o cliente lê que não há confirmação — não que "não consegui".
  #
  # RECARREGA antes de decidir: o lote tem até 500 linhas processadas em sequência, e a que chega
  # aqui pode ter recebido preço (ou número) desde a consulta. Decidir pela leitura velha publicaria
  # "não consegui" ao lado do preço, ou "não consegui confirmar" de uma cotação já registrada.
  def close(run)
    native = ::Autonomia::Agents::Tools::Registry.find(run.slug)
    run.reload
    tell_customer(run, native) if native.present? && run.delivered_count.zero?
    run.finish!('failed', failure_code: 'execucao_abandonada')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] reap failed run=#{run.id} #{e.class}")
    nil
  end

  # Força a publicação: a cadeia de entrega humanizada daquele turno já morreu há muito, e esperar
  # por ela deixaria o cliente sem desfecho para sempre.
  def tell_customer(run, native)
    texto = run.envio_incerto? ? native.uncertain_message : native.failure_message
    ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(texto)
  end
end

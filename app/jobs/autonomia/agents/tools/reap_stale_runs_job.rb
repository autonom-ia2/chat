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
  # encerra, a cotação não pede outro PDF para a mensagem que já está no banco
  # (`InsuranceQuote::Comparativo#comparativo_assumido?`), o Redis voltar não dispara nada. Este é
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
    encerrar(run, native) if native.present?
    run.finish!('failed', failure_code: 'execucao_abandonada')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] reap failed run=#{run.id} #{e.class}")
    nil
  end

  # O MESMO ENCERRAMENTO DO MOTOR (`Tools::Encerramento`, entrega 8). Até 12/09/2026 este caminho
  # publicava a frase de falha e só ela, sem passar pela ferramenta: quem já tinha recebido preço
  # lia "não consegui" — ou, com `delivered_count` positivo, não lia nada. Era o defeito que o motor
  # já tinha corrigido, intacto na outra porta, e fora do alcance da correção de lá porque o
  # varredor não passa por `fail_run`.
  #
  # O QUE MUDA AQUI, HOJE, É A FRASE — e só ela. O caminho das entregas fica aberto para a
  # ferramenta que tem algo PRONTO (a 8b), mas a cotação não tem: com `trabalho_novo: false` o
  # `closing_deliveries` dela devolve `[]`, sempre, porque o comparativo só existe depois de uma
  # chamada ao portal. Dizer o contrário seria prometer um arquivo que este caminho não entrega.
  #
  # E A FRASE MUDA PARA MAIS, NÃO SÓ PARA MELHOR: com contador positivo esta porta CALAVA, e agora
  # ela fala. É o certo em quase todo estado — quem recebeu preço merece um desfecho —, mas na
  # janela do R18 (a passada que morre entre o aceite do comparativo e o `record_attempt!`) ela
  # publica a frase parcial para quem recebeu TUDO, onde a `main` ficava em silêncio. Medida na
  # rodada 6 e aceita por decisão registrada. NÃO é a única regressão declarada da entrega — a
  # rodada 6 escreveu isso e era falso: R19 também é, pela ponta em que a lista de identidades
  # regravada faz o fecho CALAR onde a `main` publicava pelo contador (rodada 7).
  #
  # A publicação é FORÇADA (`publish!`): a cadeia de entrega humanizada daquele turno já morreu há
  # muito, e esperar por ela deixaria o cliente sem desfecho para sempre.
  #
  # E AQUI NÃO SE COMEÇA TRABALHO NOVO NO PORTAL (`trabalho_novo: false`). Este
  # caminho não é um job por execução: é um lote de até `BATCH_LIMIT` linhas processadas EM SEQUÊNCIA
  # dentro de um cron, e a cotação abandonada com preço pediria ao portal a geração do comparativo —
  # login mais uma chamada de até 60 s, mais o download — uma vez por linha. Com os 25 s de shutdown
  # do Sidekiq, um deploy no meio do lote mata a passada e joga o resto das linhas para a varredura
  # seguinte, 10 min depois — com o cliente esperando desde o começo. Então sai só o que já está
  # pronto, e o fecho diz a verdade sobre o que o cliente tem.
  #
  # O FECHO ENCADEADO AINDA ESPERA (rodada 2 da fatia 1 do PDF rápido, 13/09/2026). Forçar ignora a cadeia
  # do turno, não a entrega de que o fecho depende (`Tools::EntregaEncadeada`, o comparativo adiado que
  # ainda não é mensagem): o publicador devolve `deferred`, e o `AsyncPublishJob` enfileirado aqui já
  # começa com a cadeia no teto e espera só a entrega.
  def encerrar(run, native)
    ::Autonomia::Agents::Tools::Encerramento
      .new(run: run, native: native, trabalho_novo: false) { |entrega| publicar_forcado(run, entrega) }.encerrar
  end

  def publicar_forcado(run, entrega)
    config = ::Autonomia::Agents::Tools::AsyncConfig
    result = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish!(entrega)
    if result.deferred?
      ::Autonomia::Agents::Tools::AsyncPublishJob.set(wait: config::PUBLISH_DEFER_SECONDS.seconds)
                                                 .perform_later(run.id, result.adiada || entrega, config::MAX_PUBLISH_DEFERRALS)
    end
    result
  end
end

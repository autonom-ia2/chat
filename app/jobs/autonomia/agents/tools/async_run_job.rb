# MOTOR da ferramenta assíncrona (#313): submete, consulta de tempos em tempos, publica.
#
# NÃO SEGURA WORKER. Cada execução é curta (uma submissão ou uma consulta) e se re-agenda com
# `set(wait:)` até acabar — mesmo desenho de `EmailCampaigns::Ai::PollJob`, que já roda em
# produção. Dormir os ~90s da cotação dentro do job seria pior do que parece: o Sidekiq desta
# instalação tem `:timeout: 25` de shutdown, então TODO deploy mataria a espera no meio, e o
# `:max_retries: 3` reexecutaria o job do zero — o que aqui significa cotar de novo na
# seguradora, com custo e duplicidade no portal do corretor.
#
# NUNCA deixa exceção subir. Deixar o Sidekiq reexecutar refaria o `start`; aqui uma falha ou é
# uma nova tentativa controlada (dentro do prazo) ou é o fim com mensagem honesta ao cliente.
# Silêncio nunca é opção: o cliente está esperando.
class Autonomia::Agents::Tools::AsyncRunJob < ApplicationJob
  queue_as :medium

  AsyncConfig = ::Autonomia::Agents::Tools::AsyncConfig

  # Marca nossa, gravada no handle junto com o que a ferramenta devolveu. É ela que diz "já
  # submeti" — não o conteúdo do handle. Sem isso, uma ferramenta que devolvesse nil ou {} faria a
  # passada seguinte chamar `start` DE NOVO, até 60 vezes: 60 cotações reais no portal.
  SUBMITTED_KEY = 'autonomia_submitted'.freeze
  # MESMA IDEIA DO `SUBMITTED_KEY`, para o outro extremo da execução. O encerramento publica e só
  # DEPOIS `finish!` registra o desfecho: um sinal de shutdown no meio (deploy) deixaria a execução
  # em `running`, e o retry do Sidekiq reentraria. A marca é gravada ANTES de publicar.
  #
  # HONESTIDADE SOBRE O QUE ESTÁ PROVADO: não consegui reproduzir essa reentrada em teste — forçar
  # o status de volta para `running` não faz o job reentrar no encerramento. O spec trava que a
  # marca é gravada (pega a remoção acidental); a proteção contra o retry é raciocínio, como era a
  # do `SUBMITTED_KEY` quando ele nasceu.
  CLOSED_KEY = 'autonomia_closed'.freeze

  def perform(run_id, attempt = 0)
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank? || !run.running?

    native = ::Autonomia::Agents::Tools::Registry.find(run.slug)
    return if stop?(run, native, attempt.to_i)

    notify_start(run, native)
    advance(run, native, attempt.to_i)
  end

  private

  # Motivos para NÃO dar mais um passo. Verificados antes de qualquer chamada ao portal — cada passo
  # é uma cotação de verdade, com custo e registro na seguradora.
  def stop?(run, native, attempt)
    if native.blank?
      fail_run(run, nil, 'ferramenta_indisponivel')
    elsif run.agent.blank?
      fail_run(run, native, 'agente_indisponivel')
    # O operador puxou o freio (kill-switch da conta, agente desligado, conversa fora da allowlist
    # de piloto) DEPOIS do disparo. Sem esta guarda o job seguiria cotando por até 60 tentativas
    # contra a vontade de quem desligou.
    elsif ::Autonomia::Agents::Operate.authorized_agent_inbox(run.conversation).blank?
      block_run(run)
    elsif run.expired? || attempt >= AsyncConfig::MAX_ATTEMPTS
      fail_run(run, native, 'prazo_esgotado')
    else
      return false
    end
    true
  end

  # Aviso de espera escrito pelo CÓDIGO, publicado só quando o turno ficou em silêncio (o
  # modelo emitiu o sinal de silêncio, a IA falhou, ou a porta de engajamento fechou). Sem
  # isto, o cliente que se despede na mesma mensagem em que pede a cotação recebe zero
  # confirmação e, um minuto depois, uma cotação caindo do nada.
  def notify_start(run, native)
    return unless run.notify_customer && run.sequence.zero?

    publish(run, native.waiting_message)
  end

  # Submete (primeira passada) ou consulta (demais). A ferramenta é instanciada a cada
  # execução: ela resolve conexão e credencial sozinha, e nada disso trafega pelo Redis.
  #
  # JANELA CONHECIDA (#337): entre `tool.start` e `record_attempt!` não há atomicidade. Se o worker
  # morrer aí — um deploy no meio, por exemplo —, a cotação FOI feita no portal e não ficou
  # registrada; o Sidekiq reexecuta e cota de novo na seguradora.
  #
  # Um lock em volta do `submitted?` NÃO resolve isto: o problema não é duas execuções concorrentes,
  # é o efeito externo já ter acontecido sem registro. A correção é inverter a ordem — marcar a
  # intenção antes de submeter e decidir o que fazer quando existir marca sem handle —, e isso é
  # mudança de desenho, não de linha. Deixada para a issue própria em vez de improvisada aqui.
  def advance(run, native, attempt)
    tool = native.new(agent: run.agent, params: run.arguments)
    unless submitted?(run)
      handle = tool.start
      registrar_recusa(run, handle)
      run.record_attempt!(handle: submitted_handle(handle))
      return reschedule(run, attempt)
    end

    apply(run, native, tool.poll(handle: tool_handle(run), attempt: attempt), attempt)
  rescue StandardError => e
    # NUNCA ecoar e.message: a exceção pode carregar requisição assinada ou texto vindo do
    # portal. Só a classe vai ao log; ao cliente vai a NOSSA frase.
    Rails.logger.warn("[autonomia][tool][async] run=#{run.id} slug=#{run.slug} #{e.class}")
    retry_or_fail(run, native, attempt)
  end

  # A SEGUNDA PORTA DE RECUSA (entrega 6): a conferência do turno passou (ou caiu) e a validação do
  # `start` recusou. A ferramenta devolve handle com `pedido` — o contrato que `poll` já reconhece —
  # e é AQUI, não nela, que se sabe a conversa e o agente. Registrar nunca derruba a execução: a
  # entrega do pedido ao cliente vale mais que a nossa linha de log.
  def registrar_recusa(run, handle)
    return unless handle.is_a?(Hash) && handle['pedido'].present?

    ::Autonomia::Agents::Tools::Recusa.registrar(handle['motivo'], slug: run.slug, conversa: run.conversation_id,
                                                                   agente: run.agent, faltando: handle['faltando'], onde: 'envio')
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] registro de recusa falhou run=#{run.id} #{e.class}")
  end

  def apply(run, native, progress, attempt)
    Array(progress&.deliveries).each { |text| deliver(run, text) }
    run.record_attempt!(handle: merged_handle(progress&.handle))

    if progress.nil? || progress.failed?
      fail_run(run, native, progress&.failure_code)
    elsif progress.done?
      finish_done(run, native)
    else
      reschedule(run, attempt)
    end
  end

  # Entrega da FERRAMENTA (não o aviso, não a frase de falha). Conta como entregue tanto a publicada
  # quanto a ADIADA — a adiada sai sozinha pelo `AsyncPublishJob`, e tratá-la como "nada entregue"
  # faria o desfecho publicar "não consegui concluir" ao lado da cotação que estava a caminho.
  def deliver(run, text)
    result = publish(run, text)
    run.record_delivery! if result.published? || result.deferred?
    result
  end

  # Terminou sem NADA entregue (todas as seguradoras mudas, por exemplo): o cliente precisa saber.
  # Terminar em silêncio é o pior desfecho para quem está esperando — e dizer "não consegui" ao lado
  # de uma cotação entregue é o segundo pior.
  def finish_done(run, native)
    publish(run, native.failure_message) if run.delivered_count.zero?
    run.finish!('done')
  end

  # ACABAR SEM FECHAR TAMBÉM É UM DESFECHO. A guarda `delivered_count.zero?` está certa no que ela
  # evita — dizer "não consegui" a quem acabou de receber preço desmente o que ele está lendo —, mas
  # o efeito era o cliente ficar sem NADA: em 08/09/2026 uma cotação entregou cinco preços, estourou
  # o prazo, e a conversa simplesmente parou, sem comparativo e sem uma palavra.
  #
  # Agora, quando já houve entrega, a ferramenta ganha a chance de entregar o que ainda vale (o
  # comparativo em PDF) e o cliente recebe um fecho que não desmente os preços.
  def fail_run(run, native, code)
    if native.present?
      run.delivered_count.zero? ? publish(run, native.failure_message) : encerrar(run, native)
    end
    run.finish!('failed', failure_code: code.presence || 'tool_failed')
  end

  # NUNCA levanta: o encerramento é cortesia sobre um caminho que já deu errado, e falhar aqui
  # apagaria o `finish!` que registra o desfecho.
  def encerrar(run, native)
    return if run.handle.to_h[CLOSED_KEY].present?

    run.record_attempt!(handle: run.handle.to_h.merge(CLOSED_KEY => true))
    fechamento(run, native).each { |texto| publish(run, texto) }
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool] encerramento falhou slug=#{run.slug} #{e.class}")
  end

  # O que sai na despedida: o que a ferramenta ainda tem para entregar, e o fecho.
  #
  # SEM AGENTE NÃO SE MONTA A FERRAMENTA — e isto não é defesa sobrando: `agente_indisponivel` é um
  # dos caminhos que chegam aqui, alcançado JUSTAMENTE porque o agente sumiu.
  def fechamento(run, native)
    return [native.partial_message] if run.agent.blank?

    tool = native.new(agent: run.agent, params: run.arguments)
    Array(tool.closing_deliveries(run.handle)) + [native.partial_message]
  end

  # Parada por decisão do operador: sem mensagem ao cliente. Publicar aqui seria furar exatamente o
  # gate que mandou parar.
  def block_run(run)
    run.finish!('blocked', failure_code: 'nao_autorizado')
  end

  def retry_or_fail(run, native, attempt)
    run.record_attempt!
    return fail_run(run, native, 'tool_failed') if run.expired? || attempt + 1 >= AsyncConfig::MAX_ATTEMPTS

    reschedule(run, attempt)
  end

  def reschedule(run, attempt)
    self.class.set(wait: AsyncConfig.interval_for(run.agent, attempt))
        .perform_later(run.id, attempt + 1)
  end

  # A publicação é ADIADA enquanto a entrega humanizada do turno ainda está em curso —
  # publicar no meio dela entregaria a cotação antes da frase que a promete.
  def publish(run, text)
    result = ::Autonomia::Agents::Tools::AsyncPublisher.new(run: run).publish(text)
    if result.deferred?
      ::Autonomia::Agents::Tools::AsyncPublishJob
        .set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
        .perform_later(run.id, text, 1)
    end
    result
  end

  # "Já submeti?" é a NOSSA marca, não o conteúdo do handle. Sem ela, uma ferramenta que devolvesse
  # nil ou {} no `start` faria a passada seguinte submeter de novo — até 60 vezes, cada uma uma
  # cotação real no portal, que é exatamente o custo que este job existe para evitar.
  def submitted?(run)
    run.handle.is_a?(Hash) && run.handle[SUBMITTED_KEY].present?
  end

  # O handle da FERRAMENTA, sem a nossa marca: ela não precisa conhecer o nosso controle.
  def tool_handle(run)
    run.handle.to_h.except(SUBMITTED_KEY)
  end

  def submitted_handle(handle)
    { SUBMITTED_KEY => true }.merge(handle.is_a?(Hash) ? handle : {})
  end

  # A consulta só atualiza o handle quando a ferramenta devolve um novo; a marca é preservada.
  def merged_handle(handle)
    return nil unless handle.is_a?(Hash) && handle.present?

    { SUBMITTED_KEY => true }.merge(handle)
  end
end

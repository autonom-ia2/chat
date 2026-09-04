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
  SUBMITTED_KEY = 'autonomia_submitted'.freeze

  # Marca nossa, gravada no handle junto com o que a ferramenta devolveu. É ela que diz "já
  # submeti" — não o conteúdo do handle. Sem isso, uma ferramenta que devolvesse nil ou {} faria a
  # passada seguinte chamar `start` DE NOVO, até 60 vezes: 60 cotações reais no portal.
  SUBMITTED_KEY = 'autonomia_submitted'.freeze

  def perform(run_id, attempt = 0)
    run = ::Autonomia::Agents::ToolRun.find_by(id: run_id)
    return if run.blank? || !run.running?

    native = ::Autonomia::Agents::Tools::Registry.find(run.slug)
    return fail_run(run, nil, 'ferramenta_indisponivel') if native.blank?
    return fail_run(run, native, 'agente_indisponivel') if run.agent.blank?
    return fail_run(run, native, 'prazo_esgotado') if run.expired? || attempt.to_i >= AsyncConfig::MAX_ATTEMPTS

    notify_start(run, native)
    advance(run, native, attempt.to_i)
  end

  private

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
  def advance(run, native, attempt)
    tool = native.new(agent: run.agent, params: run.arguments)
    unless submitted?(run)
      run.record_attempt!(handle: submitted_handle(tool.start))
      return reschedule(run, attempt)
    end

    apply(run, native, tool.poll(handle: tool_handle(run), attempt: attempt), attempt)
  rescue StandardError => e
    # NUNCA ecoar e.message: a exceção pode carregar requisição assinada ou texto vindo do
    # portal. Só a classe vai ao log; ao cliente vai a NOSSA frase.
    Rails.logger.warn("[autonomia][tool][async] run=#{run.id} slug=#{run.slug} #{e.class}")
    retry_or_fail(run, native, attempt)
  end

  def apply(run, native, progress, attempt)
    Array(progress&.deliveries).each { |text| publish(run, text) }
    run.record_attempt!(handle: merged_handle(progress&.handle))

    if progress.nil? || progress.failed?
      fail_run(run, native, progress&.failure_code)
    elsif progress.done?
      finish_done(run, native)
    else
      reschedule(run, attempt)
    end
  end

  # Terminou sem NADA entregue (todas as seguradoras mudas, por exemplo): o cliente precisa
  # saber. Terminar em silêncio é o pior desfecho para quem está esperando.
  def finish_done(run, native)
    publish(run, native.failure_message) if run.sequence.zero?
    run.finish!('done')
  end

  def fail_run(run, native, code)
    publish(run, native.failure_message) if native.present?
    run.finish!('failed', failure_code: code.presence || 'tool_failed')
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
    return unless result.deferred?

    ::Autonomia::Agents::Tools::AsyncPublishJob
      .set(wait: AsyncConfig::PUBLISH_DEFER_SECONDS.seconds)
      .perform_later(run.id, text, 1)
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

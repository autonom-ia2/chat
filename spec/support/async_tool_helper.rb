# Constrói uma ferramenta nativa ASSÍNCRONA de teste (#313). As nativas de verdade vivem num catálogo
# FECHADO (`Tools::Registry`), então o teste usa uma classe anônima e faz o `Registry.find` apontar
# para ela — mesmo padrão de `spec/services/autonomia/agents/tools/bound_spec.rb`, que já testa as
# síncronas com classe anônima.
module AsyncToolHelper
  # `poll` aceita um Progress fixo ou um lambda que recebe (attempt) e devolve um Progress —
  # é assim que se testa "parcial no 1º, final no 2º".
  # `precheck` aceita texto (o que o modelo recebe no lugar do aceite) ou um callable — que pode
  # levantar, para exercitar "conferência caiu, aceita mesmo assim".
  # rubocop:disable Metrics/ParameterLists, Metrics/MethodLength -- é um construtor de dublê:
  # cada parâmetro é um comportamento que algum exemplo precisa ligar isoladamente.
  # `resultado` e `resta` são as DUAS perguntas do desfecho com resultado (entrega 8). O
  # padrão é o do `Base` — false, false —, e é ele que faz a ferramenta genérica fechar SEM evento de resultado
  # em vez de afirmar que algo ficou pelo caminho. `a_pedir` é o resultado guardado que não chegou ao cliente
  # (fatia 3 do #420), e o desfecho é então `valores_guardados`.
  def build_async_tool(slug: 'consultar_cotacao', handle: { 'id' => 'cot-1' }, poll: nil,
                       start_error: nil, poll_error: nil, precheck: nil, closing: nil,
                       resultado: false, resta: false, a_pedir: false)
    Class.new(::Autonomia::Agents::Tools::Native::Base) do
      define_singleton_method(:slug) { slug }
      define_singleton_method(:description) { 'Ferramenta assíncrona de teste.' }
      define_singleton_method(:async?) { true }
      define_singleton_method(:accepted_message) { 'aceito: consulta iniciada' }
      # Os fatos de um evento, para o modelo (PR C). O dublê responde com o tipo, para o exemplo ver que chegou.
      define_singleton_method(:fatos_do_evento) { |tipo, _run| "fatos do dublê: #{tipo}" }

      # A conferência do turno: devolve texto ao modelo (e nenhuma execução é aberta) ou nil.
      define_method(:precheck) { precheck.respond_to?(:call) ? precheck.call : precheck }

      # O que ainda vale entregar quando a execução acaba sem fechar (o comparativo, na cotação).
      # `trabalho_novo:` é do contrato desde a entrega 8 e o dublê genérico o ignora: quem o observa
      # é `encerramento_spec`, que define o método por conta própria.
      define_method(:closing_deliveries) do |_handle, **|
        closing.respond_to?(:call) ? closing.call : Array(closing)
      end

      define_method(:resultado_entregue?) { |_handle| resultado }
      define_method(:resta_entregar?) { |_handle| resta }
      define_method(:resultado_a_pedir?) { |_handle| a_pedir }

      define_method(:start) do
        raise start_error if start_error

        handle
      end

      define_method(:poll) do |**kwargs|
        raise poll_error if poll_error

        poll.respond_to?(:call) ? poll.call(kwargs[:attempt]) : poll
      end
    end
  end
  # rubocop:enable Metrics/ParameterLists, Metrics/MethodLength

  # UMA ENTREGA DE ARQUIVO de teste, na forma serializada (PR C: o motor só publica arquivo). O download é do
  # exemplo: `stub_arquivo` responde a URL com um PDF de verdade.
  def arquivo_de_teste(url = 'https://arquivos.exemplo.test/entrega-1.pdf', nome: 'Entrega de teste.pdf')
    ::Autonomia::Agents::Tools::EntregaDeArquivo.new(url: url, nome: nome).to_h
  end

  def stub_arquivo(url = 'https://arquivos.exemplo.test/entrega-1.pdf', status: 200)
    host = URI.parse(url).host
    allow(Resolv).to receive(:getaddresses).and_call_original
    allow(Resolv).to receive(:getaddresses).with(host).and_return(['93.184.216.34'])
    stub_request(:get, url).to_return(status: status, body: "%PDF-1.4\n%%EOF\n", headers: { 'Content-Type' => 'application/pdf' })
  end

  # Os tipos dos eventos que esta execução disparou (PR C): os `EventoJob` enfileirados para ela, na ordem.
  def eventos_disparados(run)
    enqueued_jobs.select { |job| job[:job] == ::Autonomia::Agents::Operate::EventoJob && job[:args].first == run.id }
                 .map { |job| job[:args].second }
  end

  # O MODELO DA LIA, DUBLADO (PR C): toda chamada ao `Answerer` devolve esta fala. `nil` é a IA que falhou.
  # Guarda as queries que recebeu em `@queries_da_lia`, para o exemplo ver a nota do sistema.
  def lia_responde(fala = 'fala da Lia')
    @queries_da_lia = []
    allow(::Autonomia::Agents::Answerer).to receive(:new) do |**kwargs|
      @queries_da_lia << kwargs[:query]
      instance_double(::Autonomia::Agents::Answerer, answer: resposta_da_lia(fala))
    end
  end

  def queries_da_lia
    @queries_da_lia
  end

  def resposta_da_lia(fala)
    ::Autonomia::Agents::AnswerResult.new(reply: fala, confidence: 0.9, handoff: { should: false, reason: nil },
                                          raw_reply: fala, error: fala.nil? ? 'ai_unavailable' : nil)
  end

  # UM TIQUE DOS TURNOS DE EVENTO: cada `EventoJob` enfileirado roda uma vez, com os argumentos dele; o que adiar
  # volta para a fila. -> quantos rodaram.
  def rodar_eventos
    jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |job| job[:job] == ::Autonomia::Agents::Operate::EventoJob }
    ActiveJob::Base.queue_adapter.enqueued_jobs.reject! { |job| jobs.any? { |rodando| rodando.equal?(job) } }
    jobs.each { |job| ::Autonomia::Agents::Operate::EventoJob.new.perform(*job[:args]) }
    jobs.size
  end

  # Faz o catálogo devolver esta ferramenta para o slug dela (e nada para os outros).
  def register_async_tool(tool)
    allow(::Autonomia::Agents::Tools::Registry).to receive(:find) do |slug|
      slug.to_s == tool.slug ? tool : nil
    end
    allow(::Autonomia::Agents::Tools::Registry).to receive(:for_agent).and_return([tool])
    tool
  end
end

RSpec.configure do |config|
  config.include AsyncToolHelper
end

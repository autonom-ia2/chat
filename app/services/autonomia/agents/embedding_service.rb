class Autonomia::Agents::EmbeddingService
  class EmbeddingError < StandardError
    ROTULOS = %w[ai_not_configured invalid_api_base rede].freeze

    # #2850 — rótulo curto para log e telemetria. Nunca a mensagem do provedor, que pode trazer um pedaço da chave.
    def motivo
      ROTULOS.include?(message) ? message : 'provedor_recusou'
    end
  end

  # #2850 — o prazo TOTAL de uma tentativa estourou (o do Faraday vale por operação: abrir, escrever, cada leitura). É um
  # Timeout::Error: se estourar dentro do Net::HTTP, o Faraday o converte em Faraday::TimeoutError, motivo `prazo` também.
  class PrazoTotal < Timeout::Error; end

  # #2850 — falha que pode passar numa nova tentativa (prazo, conexão, provedor fora, limite de taxa). `motivo` é um
  # rótulo curto para log e telemetria. O Retriever decide se tenta de novo; quem não trata recebe um EmbeddingError.
  class Passageira < EmbeddingError
    attr_reader :motivo

    def initialize(motivo)
      @motivo = motivo
      super("Failed to create an embedding: #{motivo}")
    end
  end

  # O erro de prazo e de conexão vem do Faraday, sem passar pelo RubyLLM::Error.
  PASSAGEIRAS = {
    PrazoTotal => 'prazo',
    Faraday::TimeoutError => 'prazo',
    Faraday::ConnectionFailed => 'conexao',
    Faraday::SSLError => 'conexao',
    RubyLLM::ServerError => 'provedor',
    RubyLLM::ServiceUnavailableError => 'provedor',
    RubyLLM::OverloadedError => 'provedor',
    RubyLLM::RateLimitError => 'limite_de_taxa'
  }.freeze

  # api_base padrão da OpenAI. O RubyLLM já tem o seu próprio default (com o path correto), então
  # quando a credencial da conta vem com este host "pelado" (sem /v1) NÃO repassamos o base — senão
  # a URL de embeddings sai errada e o provedor responde erro. Só repassamos base de provedor custom.
  OPENAI_DEFAULT_BASE = 'https://api.openai.com'.freeze

  # Nº de textos por request de embedding no batch. A API da OpenAI aceita muitos inputs por chamada;
  # 96 equilibra latência (menos round-trips) e o teto de tokens do request. B1: corta o custo de
  # tempo/erro do batch ingênuo (1 request por chunk) sem mudar o vetor produzido.
  EMBED_BATCH_SIZE = 96

  # `model:` explícito (opcional) trava o modelo p/ TODA a operação (Ingestor/Retriever resolvem 1x e
  # passam aqui) — evita que uma troca de config no meio de embed/retrieve/write compare/grave vetor de
  # dimensão diferente na coluna errada. Também habilita o backfill (força 3-large sem virar o global).
  # `prazo:` (segundos, opcional) — #2850: prazo por tentativa, sem as repetições do RubyLLM. Sem ele (ingestão em
  # lote, fora do turno do cliente), ficam os padrões do RubyLLM.
  def initialize(account:, model: nil, prazo: nil)
    Llm::Config.initialize!
    @account = account
    @model = model.presence || Autonomia::Agents::Config.active_embedding_model
    @prazo = prazo
  end

  # text -> Array<Float> (dim do modelo: 1536 no 3-small, 3072 no 3-large). Retorna [] se vazio.
  # RubyLLM::Error -> EmbeddingError. Usa a chave OpenAI DA CONTA (mesma do Construtor/Answerer, via
  # CredentialResolver), pois a config GLOBAL do RubyLLM (Llm::Config) não tem chave nesta instalação.
  def embed(text)
    return [] if text.blank?

    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # A credencial (banco) e o guarda do api_base (DNS) ficam fora do prazo: interromper uma consulta no meio deixaria a
    # conexão do banco quebrada pelo resto do job.
    contexto = context
    dentro_do_prazo { contexto.embed(text, model: @model).vectors }
  rescue *PASSAGEIRAS.keys => e
    log_failure(e, started_at: started_at)
    raise Passageira, PASSAGEIRAS.find { |classe, _motivo| e.is_a?(classe) }.last
  rescue Faraday::Error => e
    # O resto do Faraday (resposta cortada, por exemplo) não é RubyLLM::Error: sem isto escaparia sem log nem motivo.
    log_failure(e, started_at: started_at)
    raise EmbeddingError, 'rede'
  rescue RubyLLM::Error => e
    log_failure(e, started_at: started_at)
    raise EmbeddingError, "Failed to create an embedding: #{e.message}"
  end

  # Array<String> -> Array<Array<Float>>, alinhado 1:1 com a entrada (texto vazio -> []). Faz UMA
  # chamada por lote de EMBED_BATCH_SIZE (input em array), não 1 por texto. Preserva a posição: os
  # não-vazios vão à API em lote e voltam para os seus índices; vazios ficam []. Se um lote falhar,
  # o erro sobe (EmbeddingError) — o Ingestor decide (não silencia).
  def embed_batch(texts)
    list = Array(texts)
    result = Array.new(list.size, [])
    list.each_index.reject { |i| list[i].blank? }.each_slice(EMBED_BATCH_SIZE) do |indices|
      vectors = embed_many(indices.map { |i| list[i] })
      indices.each_with_index { |orig_i, k| result[orig_i] = vectors[k] || [] }
    end
    result
  end

  private

  # UMA chamada de embedding com input em array -> Array<Array<Float>> na mesma ordem. RubyLLM devolve
  # `vectors` como array-de-arrays quando a entrada é array; se algum provider devolver um vetor único
  # (input de 1), normaliza p/ array-de-arrays.
  def embed_many(texts)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    vectors = context.embed(texts, model: @model).vectors
    vectors.first.is_a?(Array) ? vectors : [vectors]
  rescue RubyLLM::Error => e
    log_failure(e, started_at: started_at)
    raise EmbeddingError, "Failed to create an embedding: #{e.message}"
  end

  # Contexto RubyLLM com a chave da conta. Memoizado (reusado no batch). Não repassa o api_base
  # quando é o host padrão da OpenAI (deixa o RubyLLM usar o default correto).
  def context
    @context ||= begin
      cred = Crm::Ai::CredentialResolver.new(account: @account).resolve
      raise EmbeddingError, 'ai_not_configured' if cred.blank?

      @api_host = host_da(cred)
      base = cred[:api_base].to_s.chomp('/')
      base = nil if base.blank? || base == OPENAI_DEFAULT_BASE
      # SSRF: api_base custom controlado pela conta é validado (HTTPS + bloqueio de host/IP
      # interno/loopback/link-local/metadata, literal E resolvido por DNS) ANTES de tocar a rede —
      # mesmo guard do Crm::Ai::ResponsesClient (paridade). Host interno -> EmbeddingError.
      if base.present?
        begin
          base = ::Crm::Ai::ApiBaseGuard.validate!(base)
        rescue ::Crm::Ai::ApiBaseGuard::BlockedError
          raise EmbeddingError, 'invalid_api_base'
        end
      end
      RubyLLM.context do |config|
        config.openai_api_key = cred[:api_key]
        config.openai_api_base = base if base.present?
        com_prazo(config)
      end
    end
  end

  # #2850 — com prazo, a tentativa inteira cabe nele (o Timeout, como no `total_timeout` do Crm::Ai::ResponsesClient).
  def dentro_do_prazo(&)
    return yield if @prazo.nil?

    Timeout.timeout(@prazo, PrazoTotal, &)
  end

  def com_prazo(config)
    return if @prazo.nil?

    config.request_timeout = @prazo
    config.max_retries = 0
  end

  def log_failure(error, started_at:)
    latency = started_at ? ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round : nil
    Rails.logger.error(
      "[crm][ai][openai_error] operation=autonomia.embedding model=#{@model} error_type=#{error.class.name} " \
      "account_id=#{@account&.id} api_host=#{api_host} latency_ms=#{latency} " \
      "message=#{error.message.to_s.truncate(300)}"
    )
  end

  # #2850 — o host do log sai da credencial já lida pelo `context`. Relê-la aqui somaria outra consulta ao banco depois do
  # prazo estourado, fora do orçamento do turno.
  attr_reader :api_host

  def host_da(cred)
    base = cred.to_h[:api_base].to_s.strip.presence || OPENAI_DEFAULT_BASE
    URI.parse(base).host
  rescue URI::InvalidURIError
    nil
  end
end

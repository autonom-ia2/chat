# Step 2 of the search by conversation (#2277): a reader model applies the plan's rule to one batch of conversations
# and returns who is in (certeza, provavel) or almost in (fora). Up to PARALLEL batches of the same search run at
# once, in threads that only talk HTTP: the transcripts are built before and the results and the usage are written
# after, on the job's own database connection.
#
# The reader is told to answer with the conversation number, and sometimes answers "CONVERSA 4812": only the
# digits count, and a number outside the batch is dropped (the eval saw none invented, but the list must never get
# someone the reader did not read). A conversation listed twice keeps the strongest group.
class ConversationAudience::Reader
  MODEL = 'gpt-6-luna'.freeze
  EFFORT = 'medium'.freeze
  FEATURE = 'campaign_conversation_audience_read'.freeze
  PARALLEL = 6
  TIMEOUT = 120

  Result = Struct.new(:batch, :people, :usage, :error, keyword_init: true)

  SCHEMA = {
    name: 'publico',
    schema: {
      type: 'object', additionalProperties: false, required: ['pessoas'],
      properties: {
        pessoas: {
          type: 'array',
          items: {
            type: 'object', additionalProperties: false, required: %w[conversa grupo motivo provas],
            properties: {
              conversa: { type: 'string' },
              grupo: { type: 'string', enum: ConversationAudiencePerson::GROUPS },
              motivo: { type: 'string' },
              provas: { type: 'array', items: { type: 'string' } }
            }
          }
        }
      }
    }
  }.freeze

  def self.instructions(plan)
    <<~TEXT
      Você lê conversas de WhatsApp de uma empresa e decide quem entra num público de campanha.
      Cada conversa é de uma pessoa (o CLIENTE). EQUIPE é uma pessoa da empresa; ASSISTENTE é a assistente automática da empresa.

      Regra do público: #{plan['rule']}
      - certeza: #{plan['sure']}
      - provavel: #{plan['likely']}
      - fora: #{plan['near']}

      Use "fora" só para quem QUASE segue a regra (fez parte do que foi pedido e falta uma peça), para a pessoa decidir.
      Quem não tem nada a ver com o pedido não é "fora": não liste.

      Para cada conversa que entra (certeza ou provavel) ou quase entra (fora), devolva um item:
      - conversa: o número que aparece em "=== CONVERSA N".
      - grupo: certeza, provavel ou fora.
      - motivo: uma frase curta e simples em português, dizendo o que a pessoa fez, com datas (ex.: "Cotou Itália em 12/09 e não fechou").
      - provas: os carimbos [MM-DDTHH:MM] das mensagens que provam (de preferência do CLIENTE).
      Conversa sem relação com a regra: não liste. Liste cada conversa no máximo uma vez.
      Não invente: use só o que está escrito na conversa.
    TEXT
  end

  def initialize(search, credential:)
    @search = search
    @credential = credential
    @instructions = self.class.instructions(search.plan)
  end

  # batches: [[batch, { conversation_id => text }], ...] -> [Result, ...] in the same order. Never raises: a batch
  # that failed comes back with its error and the caller decides.
  def call(batches)
    threads = batches.map { |batch, texts| Thread.new { read(batch, texts) } }
    ActiveSupport::Dependencies.interlock.permit_concurrent_loads { threads.map(&:value) }
  end

  private

  # Any failure stays with its batch (network, TLS, a bad answer): the other threads' paid results are kept. A call
  # that answered but could not be read still carries its usage, so it is charged and counts toward the ceiling.
  def read(batch, texts)
    return Result.new(batch: batch, people: [], usage: {}) if texts.empty?

    answer = client.create(model: MODEL, instructions: @instructions, input: texts.values.join("\n"), schema: SCHEMA,
                           reasoning_effort: EFFORT, timeout: TIMEOUT)
    Result.new(batch: batch, people: people_from(answer[:text], texts.keys), usage: answer[:usage])
  rescue StandardError => e
    Result.new(batch: batch, people: [], usage: answer&.dig(:usage) || {}, error: e)
  end

  # No feature/account here: the usage is recorded by the job, outside the threads (UsageRecorder writes to the DB).
  # One retry and 2 min per call keep a wave inside the semaphore's validity; a batch that still fails is retried
  # by the job on the next wave.
  def client
    Crm::Ai::ResponsesClient.new(credential: @credential, max_retries: 1,
                                 cache_key: "#{FEATURE}:#{@search.account_id}:#{@search.id}")
  end

  def people_from(text, ids)
    found = {}
    Array(JSON.parse(text)['pessoas']).each do |item|
      person = person_from(item)
      next unless ids.include?(person[:conversation_id]) && ConversationAudiencePerson::GROUPS.include?(person[:group])

      current = found[person[:conversation_id]]
      next if current && !ConversationAudiencePerson.stronger?(person[:group], current[:group])

      found[person[:conversation_id]] = person
    end
    found.values
  end

  def person_from(item)
    { conversation_id: item['conversa'].to_s.delete('^0-9').to_i, group: item['grupo'], reason: item['motivo'].to_s.first(500),
      proofs: Array(item['provas']).map(&:to_s).first(10) }
  end
end

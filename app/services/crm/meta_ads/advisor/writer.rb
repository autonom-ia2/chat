# O texto das ações do consultor, escrito pela IA (#1110, F5, §1.5). A Decision já escolheu tipo, ordem, variante
# e anúncio; o modelo só escreve, com marcadores `{{fato}}` no lugar de todo número (D5.1). O Check confere.
#
# Entra no modelo, por ação, só o subconjunto dos fatos que a ação usa (Format::TYPES), com valores crus: números,
# prazos e o nome do anúncio. Nunca título de card, contato ou texto de conversa.
#
# - Texto recusado pelo Check → uma nova tentativa, com a mesma entrada e só os códigos da recusa (o texto não é
#   ecoado). Na segunda, cada ação aprovada fica com a IA e cada recusada volta à regra (`check_failed`).
# - `applies: false` → todas pela regra (`not_applicable`).
# - Falha do provedor não é estado final: o run volta a `pending` por RETRY_AFTER (o ERROR_TTL da F4), e a leitura
#   seguinte pede de novo. O log leva só a classe e os códigos, nunca o texto.
#
# As duas tentativas contam como uma geração no teto do dia: quem reserva é a Analysis, uma vez, antes de chamar.
# → as colunas do run a gravar (writer_status, writer_reason, writer_attempts, texts, model, retry_after).
class Crm::MetaAds::Advisor::Writer
  MODEL = Crm::Ai::Config::MODEL_SUMMARY
  REASONING_EFFORT = Crm::Ai::Config::SUMMARY_REASONING_EFFORT
  FEATURE = 'anuncios_meta'.freeze
  RETRY_AFTER = 15.minutes
  # O pior caso da escrita (2 pedidos × (1 + MAX_RETRIES) chamadas de até REQUEST_TIMEOUT s, mais as esperas de
  # 1 s entre elas) fica abaixo de Analysis::STALE_WRITING: um run em `writing` só conta como abandonado quando o
  # job que o reivindicou já não pode estar vivo. Com os padrões do cliente (180 s, 2 novas tentativas), seriam
  # ~18 min, e outra aba reivindicaria o run aos 5 min, gastando outra vaga do teto e jogando fora o texto pago.
  REQUEST_TIMEOUT = 60
  MAX_RETRIES = 1
  TEXT_KEYS = %w[headline body why].freeze
  # `numbers_in_words` vem depois de `actions`: o modelo gera as chaves na ordem do schema e declara depois de ter
  # escrito os textos, não antes.
  SCHEMA = {
    name: 'meta_ads_advisor_texts',
    schema: {
      type: 'object',
      properties: {
        applies: { type: 'boolean' },
        actions: {
          type: 'array',
          items: {
            type: 'object',
            properties: { key: { type: 'string' }, headline: { type: 'string' }, body: { type: 'string' }, why: { type: 'string' } },
            required: %w[key headline body why], additionalProperties: false
          }
        },
        numbers_in_words: { type: 'boolean' }
      },
      required: %w[applies actions numbers_in_words], additionalProperties: false
    }
  }.freeze

  # actions: as ações da Decision (sem fillers); facts: os fatos do run (a moeda).
  def initialize(run:, actions:, facts:, language:)
    @run = run
    @actions = actions.map(&:deep_symbolize_keys)
    @facts = facts.to_h.deep_symbolize_keys
    @language = language
    @attempts = 0
  end

  def perform
    first = ask(input)
    return rule('not_applicable') if first['applies'] == false

    checked = check(first)
    return written(first, checked) if clean?(checked)

    second = ask(input.merge(previous_rejection: codes(checked)))
    return rule('not_applicable') if second['applies'] == false

    finish(second, check(second))
  rescue Crm::Ai::ResponsesClient::Error => e
    Rails.logger.warn("[crm][meta_ads][advisor] run=#{@run.id} error=#{e.class.name}")
    outcome('pending', 'ai_error', retry_after: RETRY_AFTER.from_now)
  end

  def input
    { language: @language, currency: @facts[:currency], actions: keyed.map { |action| action.slice(:key, :kind, :variant, :facts) } }
  end

  private

  def keyed
    @keyed ||= @actions.each_with_index.map do |action, index|
      { key: "a#{index + 1}", kind: action[:kind], variant: action[:variant], subject_key: action[:subject_key],
        facts: action[:facts].to_h.stringify_keys.slice(*Crm::MetaAds::Advisor::Format::TYPES.keys) }
    end
  end

  def ask(payload)
    @attempts += 1
    credential = Crm::Ai::CredentialResolver.new(account: @run.account).resolve
    client = Crm::Ai::ResponsesClient.new(credential: credential, feature: FEATURE, account: @run.account, max_retries: MAX_RETRIES)
    response = client.create(model: MODEL, instructions: Crm::MetaAds::Advisor::Prompt.instructions, input: payload.to_json, schema: SCHEMA,
                             reasoning_effort: REASONING_EFFORT, timeout: REQUEST_TIMEOUT)
    parsed = JSON.parse(response.fetch(:text))
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def check(answer)
    Crm::MetaAds::Advisor::Check.call(answer, keyed)
  end

  def clean?(checked)
    checked[:global].empty? && checked[:rejected].empty?
  end

  def codes(checked)
    (checked[:global] + checked[:rejected].values.flatten).uniq.sort
  end

  # Segunda resposta ainda recusada: vale a IA só nas ações aprovadas.
  def finish(answer, checked)
    return written(answer, checked) if clean?(checked)

    Rails.logger.warn("[crm][meta_ads][advisor] run=#{@run.id} check_failed=#{codes(checked).join(',')}")
    reason = answer['actions'].is_a?(Array) ? 'check_failed' : 'ai_invalid'
    texts = texts(answer, checked[:ok])
    texts.any? ? outcome('written', reason, texts: texts) : outcome('rule', reason)
  end

  def written(answer, checked)
    outcome('written', nil, texts: texts(answer, checked[:ok]))
  end

  # { "<kind>|<subject_key>" => { headline, body, why } }, com marcadores.
  def texts(answer, approved)
    entries = Array(answer['actions']).select { |entry| entry.is_a?(Hash) }.index_by { |entry| entry['key'].to_s }
    keyed.select { |action| approved.include?(action[:key]) }.to_h do |action|
      ["#{action[:kind]}|#{action[:subject_key]}", entries[action[:key]].slice(*TEXT_KEYS).transform_values { |text| text.to_s.strip }]
    end
  end

  def rule(reason)
    outcome('rule', reason)
  end

  def outcome(status, reason, texts: {}, retry_after: nil)
    { writer_status: status, writer_reason: reason, writer_attempts: @attempts, texts: texts,
      model: (MODEL if status == 'written'), retry_after: retry_after }
  end
end

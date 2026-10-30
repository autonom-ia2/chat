# Step 1 of the search by conversation (#2277): the planner model turns the request, written the person's way, into
# the rule every reader follows. It sees the request and a short sample of the account's conversations (to learn the
# business' words), never the whole account. When the request reads two ways that change the list a lot it returns
# one question; the person's answer comes back in `answer` and the planner follows it.
#
# The instructions are the ones measured in the quality eval (27/10/2026, account 3, Opus 5.5 as control). They are
# concepts, valid for any business: the rule was the lever, not the reader model nor the batch size.
class ConversationAudience::Planner
  MODEL = 'gpt-6.1-sol'.freeze
  EFFORT = 'medium'.freeze
  FEATURE = 'campaign_conversation_audience_plan'.freeze
  SAMPLE = 12
  EXCERPT = 1500
  PERIOD_WORDS = {
    '7d' => 'nos últimos 7 dias', '30d' => 'nos últimos 30 dias', '3m' => 'nos últimos 3 meses',
    '12m' => 'no último ano', 'all' => 'em todas as conversas'
  }.freeze

  SCHEMA = {
    name: 'plano_do_publico',
    schema: {
      type: 'object', additionalProperties: false,
      required: %w[entendi pergunta regra certeza provavel fora nome_sugerido],
      properties: {
        entendi: { type: 'string' },
        pergunta: {
          anyOf: [
            { type: 'null' },
            { type: 'object', additionalProperties: false, required: %w[texto opcoes],
              properties: { texto: { type: 'string' }, opcoes: { type: 'array', items: { type: 'string' } } } }
          ]
        },
        regra: { type: 'string' },
        certeza: { type: 'string' },
        provavel: { type: 'string' },
        fora: { type: 'string' },
        nome_sugerido: { type: 'string' }
      }
    }
  }.freeze

  INSTRUCTIONS = <<~TEXT.freeze
    Você ajuda uma empresa a montar um público de campanha a partir das conversas de WhatsApp dela.
    A pessoa escreveu, do jeito dela, quem quer encontrar. Ela pode escrever errado, sem acento e de forma vaga.
    Sua tarefa é transformar o pedido numa regra clara que outros leitores vão aplicar conversa por conversa.

    Devolva:
    - entendi: uma frase simples, em português do dia a dia, dizendo quem vai entrar na lista (a pessoa vai ler e confirmar).
    - pergunta: se o pedido tiver duas leituras que mudam muito a lista, a pergunta curta que você faria (texto) e as
      opções de resposta (2 ou 3, curtas, em português do dia a dia). Senão, null. Mesmo com pergunta, siga com a
      leitura mais provável nas outras respostas.
    - regra: a regra completa para os leitores, com o que conta e o que não conta, usando o vocabulário real do negócio.
    - certeza: quando a conversa mostra claramente que a pessoa segue a regra.
    - provavel: quando tudo indica que sim, mas falta um detalhe.
    - fora: quando parece relacionado mas não segue a regra (para a pessoa conferir e decidir).
    - nome_sugerido: nome curto para o público.

    Cada conversa é de uma pessoa (o CLIENTE). Mensagens de EQUIPE são de uma pessoa da empresa; de ASSISTENTE, da
    assistente automática da empresa. O que conta é o que o cliente fez ou disse, e o que aconteceu com ele na conversa.

    Cuidados com a regra:
    - Não acrescente exigências que a pessoa não pediu. Palavras que só descrevem quem costuma conversar com a empresa
      (como "as agências", "os clientes") não viram filtro extra, a não ser que a pessoa peça isso claramente.
    - Aceite prova indireta: se a pessoa fez algo que só faz quem já passou pelo que foi pedido (por exemplo, usar, acionar,
      pedir ajuda para usar, pedir de novo, trocar ou cancelar algo que só existe depois que aquilo aconteceu), isso conta.
      Diga na regra quais sinais valem.
    - Quando o pedido fala de problema, reclamação ou insatisfação, falhas do próprio atendimento da empresa também contam
      (pedido sem resposta, demora, precisar repetir ou insistir), além do que a pessoa diz com todas as letras.
    - "certeza" é só para o que está explícito (a pessoa diz, ou o fato aparece claro na conversa). O que é deduzido
      (sinais, falhas do atendimento sem queixa da pessoa) vai para "provavel".
    - Palavras vagas de quantidade ou frequência ("muito", "sempre", "pouco", "várias vezes") viram um número concreto na
      regra (por exemplo, "3 ou mais"), e você diz qual número usou.
    - "fora" é só para quem quase segue a regra e que a pessoa provavelmente gostaria de conferir; não é para todo mundo
      que fez a etapa anterior do que foi pedido.
    - "provavel" é generoso: sinais fortes de que aconteceu, mesmo sem confirmação escrita, entram como provável, porque a
      pessoa revisa a lista antes de usar. Deixar de fora quem devia estar é pior do que pôr alguém para ela conferir.
    - Se vier a resposta da pessoa à sua pergunta, siga a resposta e devolva pergunta = null. Se ela disser que tanto
      faz, siga a leitura mais provável.
  TEXT

  def initialize(search, credential:)
    @search = search
    @account = search.account
    @credential = credential
  end

  # -> [plan hash, cost in USD]. Raises Crm::Ai::ResponsesClient::Error when the AI does not answer.
  def call
    result = client.create(model: MODEL, instructions: INSTRUCTIONS, input: input, schema: SCHEMA, reasoning_effort: EFFORT)
    [plan_from(JSON.parse(result[:text])), ConversationAudience::Cost.of(MODEL, result[:usage])]
  rescue JSON::ParserError
    raise Crm::Ai::ResponsesClient::Error, 'invalid_plan'
  end

  private

  def client
    Crm::Ai::ResponsesClient.new(credential: @credential, feature: FEATURE, account: @account)
  end

  def input
    answer = @search.answer.present? ? "\nResposta da pessoa à sua pergunta: \"#{@search.answer}\"" : ''
    "Pedido da pessoa: \"#{@search.request}\"#{answer}\nPeríodo: #{PERIOD_WORDS[@search.period]}.\n\n" \
      "Amostra de conversas da conta (só para conhecer o negócio):\n\n#{sample}"
  end

  def sample
    recent = ConversationAudience::Conversations.scope(@account, @search.user, @search.since).reorder(last_activity_at: :desc)
    ids = recent.limit(SAMPLE * 10).pluck(:id)
    texts = ConversationAudience::Transcript.new(@account).for(ids.sample(SAMPLE))
    texts.values.map { |text| text.first(EXCERPT) }.join("\n\n")
  end

  def plan_from(answer)
    {
      'understood' => answer['entendi'].to_s, 'rule' => answer['regra'].to_s, 'sure' => answer['certeza'].to_s,
      'likely' => answer['provavel'].to_s, 'near' => answer['fora'].to_s, 'name' => answer['nome_sugerido'].to_s.first(255),
      'question' => question_from(answer['pergunta'])
    }
  end

  # One question per search: after the answer the plan goes on, even if the model would ask again.
  def question_from(question)
    options = Array(question && question['opcoes']).compact_blank.first(3)
    return if @search.answer.present? || options.empty?

    { 'text' => question['texto'].to_s, 'options' => options }
  end
end

# #1428 (tema 6, parte 2) — "MUDAR CONVERSANDO" APLICA O PEDIDO INTEIRO E SÓ ELE. SÓ NO PILOTO (Fase 2) e só no AJUSTE.
#
# Em 13/10 (conta 16) o chip "Me explica o que Hubber faz hoje", uma PERGUNTA, virou aplicação: o Construtor regravou os
# mesmos valores e a tela disse "Pronto". Noutro caso, "responda em no máximo 2 frases" não entrou nem na instrução nem
# no tom. As peças daqui, todas dados ou funções puras, sem estado:
#   - o schema do ajuste: o do Construtor mais `so_pergunta` e a lista `mudancas` (o modelo declara o que entendeu, e
#     a pergunta vira resposta, nunca aplicação). O BUILDER_SCHEMA de fora do piloto não muda;
#   - a TABELA DE DESTINO (onde cada tipo de pedido entra), num item developer do turno de ajuste, para não mudar a
#     instrução-mãe de quem está fora do piloto;
#   - o FILTRO: só os atributos dos campos listados vão para a gravação. O que não foi pedido fica idêntico por código,
#     não por obediência do modelo.
# Quem decide se a fala é pergunta ou pedido é o MODELO, por campo estruturado (regra do Rodrigo, 20/09/2026).
# Texto lido pelo modelo: sem travessão e sem crase.
module Autonomia::Agents::Builder::AjustePorLista
  CAMPOS = %w[instruction tone handoff_rule greeting fallback_message starter_questions guardrails human_card name
              voice].freeze

  # O que cada campo da lista leva para a gravação. A instrução leva junto o andaime e o cartão, que a acompanham.
  # `agent_type` nunca muda no ajuste; `actuation` e `with_knowledge` não são do modelo e ficam como estão.
  COLUNAS_POR_CAMPO = {
    'instruction' => %i[instruction scaffold human_card], 'tone' => %i[tone], 'handoff_rule' => %i[handoff_rule],
    'greeting' => %i[greeting], 'fallback_message' => %i[fallback_message], 'starter_questions' => %i[starter_questions],
    'human_card' => %i[human_card], 'name' => %i[name]
  }.freeze
  # `guardrails` e `voice` são chaves do jsonb `config` (o merge do apply preserva as outras).
  CHAVES_DA_CONFIG_POR_CAMPO = { 'guardrails' => 'guardrails', 'voice' => 'voice' }.freeze

  SO_PERGUNTA_DESCRIPTION =
    'Sua leitura da ULTIMA fala do dono. true quando ela e so uma pergunta ou um pedido de explicacao sobre o agente ' \
    '(ex.: "me explica o que o agente faz hoje", "por que ele respondeu assim?"), sem nenhum pedido de mudanca. Com ' \
    'true, nada e gravado: deixe mudancas vazia e escreva a resposta em next_question. false quando a fala pede ' \
    'alguma mudanca, mesmo que venha junto com uma pergunta.'.freeze

  MUDANCAS_DESCRIPTION =
    'Cada pedido de mudanca da ULTIMA fala do dono, um item por campo de destino. So os campos listados aqui sao ' \
    'gravados; o que nao estiver aqui fica exatamente como esta no agente. Vazia quando a fala e so pergunta ou quando ' \
    'voce precisa perguntar antes de mudar.'.freeze

  MUDANCA = {
    type: 'object', additionalProperties: false, required: %w[pedido campo resumo],
    properties: {
      pedido: { type: 'string', description: 'O pedido do dono, curto, com as palavras dele.' },
      campo: { type: 'string', enum: CAMPOS, description: 'O campo onde o pedido entra (veja a tabela de destino).' },
      resumo: { type: 'string', description: 'Uma frase para o dono dizendo o que mudou nesse campo.' }
    }
  }.freeze

  # O schema do Construtor com os dois campos novos. `next_question` ganha a descrição do que ela leva no ajuste.
  SCHEMA = begin
    base = Autonomia::Agents::Builder::BUILDER_SCHEMA[:schema]
    propriedades = base[:properties].merge(
      next_question: { type: 'string',
                       description: 'A pergunta ao dono. No ajuste, quando so_pergunta=true, a resposta a pergunta dele, ' \
                                    'curta e em portugues simples.' },
      so_pergunta: { type: 'boolean', description: SO_PERGUNTA_DESCRIPTION },
      mudancas: { type: 'array', items: MUDANCA, description: MUDANCAS_DESCRIPTION }
    )
    { name: 'autonomia_agent_build_ajuste',
      schema: base.merge(properties: propriedades, required: base[:required] + %w[so_pergunta mudancas]) }.freeze
  end

  TABELA_DE_DESTINO = <<~TXT.freeze
    CONTEXTO INTERNO (nao e fala do usuario). AJUSTE POR LISTA DE MUDANCAS.
    Antes de mexer em qualquer campo, leia a ULTIMA fala do dono e decida:
    1. Se ela e so uma pergunta ou um pedido de explicacao, sem pedido de mudanca: so_pergunta=true, mudancas vazia,
       needs_more_info=true e a resposta, curta e em portugues simples, em next_question. Nao mude nada.
    2. Se ela pede mudancas: liste CADA pedido em mudancas, um item por campo de destino. So o que estiver listado e
       gravado. O que nao estiver listado fica exatamente como esta, mesmo que voce o reescreva. Devolva os outros
       campos com o valor atual.
    3. Se um pedido e impossivel, contraditorio ou vago demais para aplicar com seguranca, nao o liste: pergunte em
       next_question (needs_more_info=true). Os pedidos claros da mesma fala voce aplica normalmente.
    ONDE CADA PEDIDO ENTRA:
    - tamanho, formato ou estilo da resposta (ex.: "responda em no maximo 2 frases", "sem emoji"): tone E instruction,
      um item para cada.
    - quando passar para uma pessoa da equipe, ou o que passar (ex.: "preco passa para a equipe"): handoff_rule, e
      tambem instruction quando muda o que o agente faz na conversa.
    - assunto que o agente nao pode tratar ou limite (ex.: "nao fale de preco"): guardrails E instruction.
    - o que o agente faz, sabe, pergunta ou coleta: instruction.
    - a primeira mensagem ao cliente: greeting.
    - o que dizer quando nao souber responder: fallback_message.
    - as sugestoes de perguntas iniciais: starter_questions.
    - a descricao do agente para o dono: human_card.
    - o nome do agente: name. A voz (feminina ou masculina): voice.
    EXCECAO: um pedido do dono MAIS RESTRITO que o padrao, ou que uma regra geral que ja existe (ex.: "no maximo 2
    frases" quando a instrucao ja diz "seja breve"), SEMPRE e gravado nos campos acima. Nunca descarte um pedido por
    parecer coberto por outra regra.
    Nunca mude o tipo do agente.
  TXT

  # Sem pedido para aplicar e sem resposta do modelo: nunca um "Pronto" falso.
  SEM_PEDIDO = 'Não encontrei uma mudança para fazer nessa mensagem. O que você quer mudar no agente?'.freeze
  INCOMPLETO = 'Preciso de um pouco mais de contexto para fazer essa mudança. Pode detalhar melhor?'.freeze
  PEDIDO_MAX_CHARS = 2_000

  module_function

  def schema
    SCHEMA
  end

  def item_da_tabela
    { role: 'developer', content: [{ type: 'input_text', text: TABELA_DE_DESTINO }] }
  end

  # O aviso da tentativa de correção, depois de uma conferência com falta.
  def item_de_correcao(conferencia)
    faltas = Array(conferencia['itens']).reject { |item| item['atendido'] == true }.map do |item|
      "- #{item['pedido']}#{" (#{item['observacao']})" if item['observacao'].present?}"
    end
    texto = ['CONTEXTO INTERNO (nao e fala do usuario). CONFERENCIA DO AJUSTE: faltou aplicar:', *faltas,
             'A configuracao atual acima ja traz o que entrou. Aplique agora so o que faltou, listando cada item em ' \
             'mudancas. Se nao for possivel aplicar, explique em next_question com needs_more_info=true.'].join("\n")
    { role: 'developer', content: [{ type: 'input_text', text: texto }] }
  end

  # A lista declarada pelo modelo, só com os itens de campo conhecido.
  def mudancas(parsed)
    Array(parsed['mudancas']).filter_map do |item|
      next unless item.is_a?(Hash) && CAMPOS.include?(item['campo'].to_s)

      { 'pedido' => item['pedido'].to_s, 'campo' => item['campo'].to_s, 'resumo' => item['resumo'].to_s }
    end
  end

  def campos(lista)
    lista.pluck('campo').uniq
  end

  # Os atributos que vão para a gravação: só os dos campos listados.
  def so_os_pedidos(attrs, lista)
    pedidos = campos(lista)
    filtrado = attrs.slice(*pedidos.flat_map { |campo| COLUNAS_POR_CAMPO.fetch(campo, []) }.uniq)
    chaves = pedidos.filter_map { |campo| CHAVES_DA_CONFIG_POR_CAMPO[campo] }
    filtrado[:config] = attrs[:config].to_h.slice(*chaves) if chaves.any?
    filtrado
  end

  # A instrução e o cartão nunca são gravados em branco (#19), quando estão na lista.
  def essencial_em_branco?(parsed, lista)
    gravados = so_os_pedidos({ instruction: parsed['instruction'], human_card: parsed['human_card'] }, lista)
    gravados.values.any? { |valor| valor.to_s.strip.blank? }
  end

  # O agente que a conferência lê: os campos versionados e a instrução.
  def retrato(agent)
    config = agent.config.to_h
    { 'name' => agent.name, 'instruction' => agent.instruction.to_s, 'tone' => agent.tone, 'greeting' => agent.greeting,
      'fallback_message' => agent.fallback_message, 'handoff_rule' => agent.handoff_rule,
      'starter_questions' => Array(agent.starter_questions), 'human_card' => agent.human_card,
      'guardrails' => Array(config['guardrails']), 'voice' => config['voice'] }
  end

  # O rascunho que a tela lê no state sai do AGENTE, não da saída do modelo: um campo que o modelo reescreveu sem
  # listar não foi gravado, e a tela não pode mostrá-lo como se fosse.
  def rascunho_do_agente(agent)
    retrato(agent).except('instruction', 'voice').merge('agent_type' => agent.agent_type)
  end

  def pedido(texto)
    texto.to_s.strip.truncate(PEDIDO_MAX_CHARS, omission: '')
  end

  # A pergunta ao dono quando a conferência achou falta depois da correção.
  def pergunta_do_que_faltou(conferencia)
    faltou = Array(conferencia['pendencias']).join('; ')
    pergunta = conferencia['pergunta'].to_s.strip.presence || 'Pode me explicar melhor o que você quer?'
    "Não consegui aplicar: #{faltou}. #{pergunta}"
  end
end

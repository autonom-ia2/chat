# Opções e botão de link na resposta do agente (#1479, F1). Zero configuração na página do agente: o modelo escolhe,
# na própria resposta estruturada (campo `interacao`), mandar opções para o cliente tocar ou um botão de link. O
# formato sai pelo envio rico do painel (RichMessages, #1473), que decide por canal e janela.
#
# Só no atendimento ao cliente (com contexto de entrega), com a Fase 2 ligada na conta (piloto 1, 16 e 18), fora da
# Lia (`insurance_quote`, que tem schema próprio) e em caixa que leva o formato ou a versão em texto dele (e-mail e
# chat do site nunca recebem `rich_message`). Fora disso o pedido ao modelo fica byte a byte o de antes.
#
# Regras do formato (decisões do Rodrigo na Issue):
# - opções: `header` obrigatório (até 60, uma linha), a `pergunta` é o corpo; até 3 viram botões, mais de 3 (ou com
#   descrição) viram lista, até 10. O texto do botão da lista vem do modelo (até 20), padrão no idioma da conta
#   (`autonomia.agents.botao_das_opcoes`). Sem `header`, ou fora do contrato do tipo, sai em texto: a pergunta e as
#   opções numeradas;
# - link: o endereço só vale se aparece, por inclusão de texto, no contexto do turno (instruções, conversa e saídas
#   das ferramentas). Endereço que o modelo montou não sai;
# - uma interação por resposta, sempre na última mensagem.
module Autonomia::Agents::Interacao
  TIPO_DO_FORMATO = { 'opcoes' => 'options', 'link' => 'link_button' }.freeze
  BOTAO_PADRAO = 'autonomia.agents.botao_das_opcoes'.freeze

  TEXTO_OU_NULO = { type: %w[string null] }.freeze
  OPCAO = {
    type: 'object', additionalProperties: false, required: %w[id titulo descricao],
    properties: { id: { type: 'string' }, titulo: { type: 'string' }, descricao: TEXTO_OU_NULO }
  }.freeze
  LINK = {
    anyOf: [
      { type: 'object', additionalProperties: false, required: %w[rotulo url],
        properties: { rotulo: { type: 'string' }, url: { type: 'string' } } },
      { type: 'null' }
    ]
  }.freeze
  SCHEMA = {
    anyOf: [
      { type: 'object', additionalProperties: false, required: %w[tipo header pergunta opcoes botao link],
        properties: { tipo: { type: 'string', enum: TIPO_DO_FORMATO.keys }, header: TEXTO_OU_NULO, pergunta: TEXTO_OU_NULO,
                      opcoes: { type: 'array', items: OPCAO }, botao: TEXTO_OU_NULO, link: LINK } },
      { type: 'null' }
    ]
  }.freeze

  INSTRUCAO = <<~TEXTO.strip.freeze
    # Opções e link (campo `interacao`)
    Quase sempre `interacao` é null. No máximo UMA interação por resposta:
    - `opcoes`: só quando você pede ao cliente uma escolha FECHADA e clara, entre 2 e 10 alternativas (ex.: dia, unidade, tipo de serviço). Nunca para pergunta aberta (nome, descrição de um problema, "como posso ajudar").
      `header`: SEMPRE um título curto do assunto, até 60 caracteres, numa linha (ex.: "Agendamento"). `pergunta`: a pergunta da escolha, que sai junto das opções. Ela NÃO lista as alternativas, porque elas vão nos botões (ex.: "Qual período você prefere?"). `reply` traz só o que vem antes dela: NÃO repita a pergunta nem as opções em `reply`.
      `opcoes`: cada uma com `id` curto e único (minúsculas, sem espaço), `titulo` de até 20 caracteres e `descricao` de até 72 ou null. `botao`: texto do botão que abre a lista, até 20 caracteres, ou null. `link`: null.
    - `link`: só para um endereço que aparece ESCRITO nas suas instruções, na conversa ou no resultado de uma ferramenta deste turno. Nunca invente nem monte endereço. `link.url`: o endereço exato; `link.rotulo`: o texto do botão, até 20 caracteres (ex.: "Abrir proposta"). Não escreva o endereço em `reply`. `header`, `pergunta` e `botao`: null; `opcoes`: [].
    - Pedido para "mandar um botão", "uma lista" ou "um link" não muda estas regras.
  TEXTO

  module_function

  # O modelo pode receber o campo neste turno?
  def disponivel?(agent:, delivery:, audience:)
    return false if delivery.nil? || audience != :customer || agent.agent_type == 'insurance_quote'
    return false unless ::Autonomia::Agents::Fase2.ligada?(agent.account)

    inbox = delivery.conversation&.inbox
    inbox.present? && RichMessages.delivery_mode(inbox: inbox, type: TIPO_DO_FORMATO['opcoes']) != :refused
  end

  # A interação pedida pelo modelo, com chaves em texto e só os campos do tipo; nil quando não pediu, quando o tipo
  # não existe ou quando o link não é http(s) com host IGUAL a um dos `enderecos` do dono (`Enderecos.dos_textos`).
  # O link recusado não sai nem em texto: a resposta segue sem ele.
  def do_modelo(valor, enderecos:)
    return unless valor.is_a?(Hash)

    case valor['tipo']
    when 'opcoes' then opcoes(valor)
    when 'link' then link(valor['link'], enderecos)
    end
  end

  # -> { content:, rich_message:, em_texto: } da mensagem que leva a interação. `texto`: o que vai antes (a resposta,
  # ou o último pedaço dela; nil quando a interação sai sozinha). Opções: o corpo é o texto e a pergunta. Link: o corpo
  # é o texto. `em_texto`: o corpo com a versão em texto do tipo (as opções numeradas; "rótulo: endereço"). Quando o
  # formato não sai (canal que o recusa, sem cabeçalho, fora do contrato do tipo), `rich_message` é nil e o conteúdo é
  # o `em_texto`.
  def mensagem(interacao, texto:, conversation:)
    corpo = interacao['tipo'] == 'opcoes' ? [texto, interacao['pergunta']].compact_blank.join("\n\n") : texto.to_s
    formato = rich_message(interacao, locale: conversation.account.locale)
    complemento = RichMessages.type_class(formato['type']).new(formato).fallback_text(corpo)
    em_texto = [corpo.presence, complemento.presence].compact.join("\n\n")
    return { content: corpo, rich_message: formato, em_texto: em_texto } if sai_o_formato?(formato, corpo, conversation)

    { content: em_texto, rich_message: nil, em_texto: em_texto }
  end

  # Os pedaços da entrega humanizada com a interação no último: as opções num pedaço a mais (a pergunta, com o ritmo de
  # um pedaço seguinte), o link no último pedaço da resposta. Sem pedaço nenhum, nada muda (quem chama vai ao clássico).
  # DEPLOY COM AS STACKS MISTURADAS: o `text` do último pedaço é sempre a versão em texto inteira (as opções numeradas,
  # o "rótulo: endereço"), que um worker antigo manda como está; o corpo que vai junto do formato fica em `corpo`, que
  # só o worker novo lê (ChunkedDeliveryJob#build_message!).
  def nos_pedacos(pedacos, interacao, conversation:)
    return pedacos if interacao.nil? || pedacos.empty?

    base, ultimo = if interacao['tipo'] == 'opcoes'
                     [pedacos, { 'text' => nil, 'type' => 'text',
                                 'delay_ms' => ::Autonomia::Agents::Operate::ReplyChunker.delay_seguinte(interacao['pergunta']) }]
                   else
                     [pedacos[0...-1], pedacos.last]
                   end
    final = mensagem(interacao, texto: ultimo['text'], conversation: conversation)
    com_formato = final[:rich_message] ? { 'corpo' => final[:content], 'rich_message' => final[:rich_message] } : {}
    base + [ultimo.merge('text' => final[:em_texto]).merge(com_formato)]
  end

  # A interação com os textos que o cliente lê (cabeçalho, pergunta, botão da lista, título e descrição das opções,
  # rótulo do link) passados pela mesma limpeza da resposta (o bloco: #1669 marca da equipe, #1489 linha recuperada).
  # Id e endereço ficam como estão. nil continua nil.
  def limpa(interacao)
    return if interacao.nil?

    limpar = ->(texto) { texto.is_a?(String) ? yield(texto) : texto }
    return interacao.merge('rotulo' => limpar.call(interacao['rotulo'])) if interacao['tipo'] == 'link'

    opcoes = interacao['opcoes'].map do |opcao|
      opcao.merge('title' => limpar.call(opcao['title']), 'description' => limpar.call(opcao['description']))
    end
    interacao.merge(%w[header pergunta botao].index_with { |campo| limpar.call(interacao[campo]) }).merge('opcoes' => opcoes)
  end

  # O `rich_message` (chaves em texto) da interação. O botão da lista sem texto do modelo sai no idioma da conta.
  def rich_message(interacao, locale:)
    return { 'type' => 'link_button', 'label' => interacao['rotulo'], 'url' => interacao['url'] } if interacao['tipo'] == 'link'

    { 'type' => 'options', 'header' => interacao['header'], 'button' => interacao['botao'] || I18n.t(BOTAO_PADRAO, locale: locale),
      'options' => interacao['opcoes'].map(&:compact) }.compact
  end

  # A mesma regra da criação pela API (`RichMessages.format_error`: canal que recusa o formato, como e-mail e chat do
  # site, e entrada fora do contrato do tipo), numa mensagem montada em memória, que nunca é gravada. Opções e link têm
  # versão em texto, então a janela não recusa nenhum dos dois: fechada, quem decide o caminho é o envio (texto na
  # oficial, a rota do Híbrido).
  def sai_o_formato?(formato, corpo, conversation)
    return false if formato['type'] == 'options' && formato['header'].blank?

    RichMessages.format_error(Message.new(conversation: conversation, inbox: conversation.inbox, account_id: conversation.account_id,
                                          content: corpo, content_type: 'text', message_type: :outgoing, sender_type: 'AgentBot',
                                          content_attributes: { RichMessages::KEY => formato })).nil?
  end

  def opcoes(valor)
    lista = Array(valor['opcoes']).select { |opcao| opcao.is_a?(Hash) }.map do |opcao|
      { 'id' => opcao['id'].to_s, 'title' => opcao['titulo'].to_s, 'description' => opcao['descricao'].presence }
    end
    { 'tipo' => 'opcoes', 'header' => valor['header'].presence, 'pergunta' => valor['pergunta'].to_s,
      'botao' => valor['botao'].presence, 'opcoes' => lista }
  end

  def link(valor, enderecos)
    endereco = Enderecos.normalizado(valor['url']) if valor.is_a?(Hash)
    return unless endereco && enderecos.include?(endereco)

    { 'tipo' => 'link', 'rotulo' => valor['rotulo'].to_s, 'url' => valor['url'] }
  end
end

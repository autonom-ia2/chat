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
#   (`autonomia.agents.botao_das_opcoes`); botão do modelo fora desse limite também sai com o padrão, e a lista
#   continua saindo. Sem `header`, ou fora do contrato do tipo, sai em texto: a pergunta e as opções numeradas;
# - link: o endereço só vale se é IGUAL a um que está escrito na instrução do agente ou na base de conhecimento, ou
#   a um que uma ferramenta do sistema devolveu neste turno dentro de um desses endereços (`Enderecos.do_dono`).
#   Endereço trazido pelo cliente, montado pelo modelo ou de mensagem já gravada não sai. O `reply` não fala do botão:
#   tem de fazer sentido sozinho se o botão não sair (link recusado: `TelemetriaDoTurno` `:link_recusado`);
# - opções sem nenhuma opção com título viram nenhuma interação;
# - uma interação por resposta, sempre na última mensagem.
# - localização (F2, flag `agentes_pedir_localizacao` por cima da Fase 2): a `pergunta` é o corpo, como nas opções; sai
#   como o botão "Enviar localização" (`location_request`) na oficial com a janela aberta e como a pergunta em texto nos
#   outros canais. A localização que o cliente manda depois vai ao turno como dado (`LocalizacaoRecebida`).
module Autonomia::Agents::Interacao
  TIPO_DO_FORMATO = { 'opcoes' => 'options', 'link' => 'link_button', 'localizacao' => 'location_request' }.freeze
  # Os tipos que levam `pergunta` como corpo.
  COM_PERGUNTA = %w[opcoes localizacao].freeze
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
  def self.schema(tipos)
    {
      anyOf: [
        { type: 'object', additionalProperties: false, required: %w[tipo header pergunta opcoes botao link],
          properties: { tipo: { type: 'string', enum: tipos }, header: TEXTO_OU_NULO, pergunta: TEXTO_OU_NULO,
                        opcoes: { type: 'array', items: OPCAO }, botao: TEXTO_OU_NULO, link: LINK } },
        { type: 'null' }
      ]
    }.freeze
  end
  SCHEMA = schema(%w[opcoes link])
  SCHEMA_COM_LOCALIZACAO = schema(%w[opcoes link localizacao])

  INSTRUCAO = <<~TEXTO.strip.freeze
    # Opções e link (campo `interacao`)
    Quase sempre `interacao` é null. No máximo UMA interação por resposta:
    - `opcoes`: só quando você pede ao cliente uma escolha FECHADA e clara, entre 2 e 10 alternativas (ex.: dia, unidade, tipo de serviço). Nunca para pergunta aberta (nome, descrição de um problema, "como posso ajudar").
      `header`: SEMPRE um título curto do assunto, até 60 caracteres, numa linha (ex.: "Agendamento"). `pergunta`: a pergunta da escolha, que sai junto das opções. Ela NÃO lista as alternativas, porque elas vão nos botões (ex.: "Qual período você prefere?"). `reply` traz só o que vem antes dela: NÃO repita a pergunta nem as opções em `reply`.
      `opcoes`: cada uma com `id` curto e único (minúsculas, sem espaço), `titulo` de até 20 caracteres e `descricao` de até 72 ou null. `botao`: texto do botão que abre a lista, até 20 caracteres, ou null. `link`: null.
    - `link`: só para um endereço que aparece ESCRITO nas suas instruções ou na base de conhecimento, ou que uma ferramenta deste turno devolveu dentro de um desses endereços. Nunca um endereço que o cliente mandou; nunca invente nem monte endereço. `link.url`: o endereço exato; `link.rotulo`: o texto do botão, até 20 caracteres (ex.: "Abrir proposta"). Não escreva o endereço em `reply` e não fale do botão nele (nada de "toque no botão"): `reply` precisa fazer sentido sozinho se o botão não sair. `header`, `pergunta` e `botao`: null; `opcoes`: [].
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

  # A conta pode receber o pedido de localização (F2)? A Fase 2 e a flag dela (`PedidoDeLocalizacao`).
  def localizacao?(account)
    PedidoDeLocalizacao.ligado?(account)
  end

  # A interação pedida pelo modelo, com chaves em texto e só os campos do tipo; nil quando não pediu, quando o tipo
  # não existe ou quando o link não é http(s) com host IGUAL a um dos `enderecos` do dono (`Enderecos.dos_textos`).
  # O link recusado não sai nem em texto: a resposta segue sem ele. O pedido de localização sem `pergunta` também não
  # sai (o botão do WhatsApp precisa de texto). Quem oferece o tipo `localizacao` é o schema (`SCHEMA_COM_LOCALIZACAO`).
  def do_modelo(valor, enderecos:)
    return unless valor.is_a?(Hash)

    case valor['tipo']
    when 'opcoes' then opcoes(valor)
    when 'link' then link(valor['link'], enderecos)
    when 'localizacao' then { 'tipo' => 'localizacao', 'pergunta' => valor['pergunta'].strip } if valor['pergunta'].to_s.strip.present?
    end
  end

  # -> { content:, rich_message:, em_texto: } da mensagem que leva a interação. `texto`: o que vai antes (a resposta,
  # ou o último pedaço dela; nil quando a interação sai sozinha). O corpo sai de `corpo`. `em_texto`: o corpo com a versão em
  # texto do tipo (as opções numeradas; "rótulo: endereço" — o link sozinho, depois do áudio, sem o rótulo repetido
  # antes). Quando o formato não sai (opções sem nenhuma opção, canal que o recusa, sem cabeçalho, fora do contrato do
  # tipo), `rich_message` é nil e o conteúdo é o `em_texto`: a pergunta das opções nunca se perde.
  def mensagem(interacao, texto:, conversation:)
    corpo = corpo(interacao, texto)
    formato = rich_message(interacao, locale: conversation.account.locale)
    complemento = RichMessages.type_class(formato['type']).new(formato).fallback_text(corpo)
    em_texto = [corpo.presence, complemento.presence].compact.join("\n\n")
    no_formato = corpo.presence || interacao['rotulo'].to_s # o link sozinho (depois do áudio): o rótulo é o corpo
    return { content: no_formato, rich_message: formato, em_texto: em_texto } if sai_o_formato?(formato, no_formato, conversation)

    { content: em_texto, rich_message: nil, em_texto: em_texto }
  end

  # Opções e localização: o texto e a pergunta, sem ela quando o texto já termina com ela (comparadas depois de strip).
  # Link: o texto.
  def corpo(interacao, texto)
    return texto.to_s unless COM_PERGUNTA.include?(interacao['tipo'])

    pergunta = interacao['pergunta'] unless repetida?(texto, interacao['pergunta'])
    [texto, pergunta].compact_blank.join("\n\n")
  end

  def repetida?(texto, pergunta)
    pergunta.present? && texto.to_s.strip.end_with?(pergunta.strip)
  end

  # Os pedaços da entrega humanizada com a interação no último: as opções num pedaço a mais (a pergunta, com o ritmo de
  # um pedaço seguinte), o link no último pedaço da resposta. Opções cuja pergunta o último pedaço já traz vão nele,
  # como o link. Sem pedaço nenhum, nada muda (quem chama vai ao clássico).
  # DEPLOY COM AS STACKS MISTURADAS: o `text` do último pedaço é sempre a versão em texto inteira (as opções numeradas,
  # o "rótulo: endereço"), que um worker antigo manda como está; o corpo que vai junto do formato fica em `corpo`, que
  # só o worker novo lê (ChunkedDeliveryJob#build_message!).
  def nos_pedacos(pedacos, interacao, conversation:)
    return pedacos if interacao.nil? || pedacos.empty?

    base, ultimo = if COM_PERGUNTA.include?(interacao['tipo']) && !repetida?(pedacos.last['text'], interacao['pergunta'])
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
    return interacao.merge('pergunta' => limpar.call(interacao['pergunta'])) if interacao['tipo'] == 'localizacao'

    opcoes = interacao['opcoes'].map do |opcao|
      opcao.merge('title' => limpar.call(opcao['title']), 'description' => limpar.call(opcao['description']))
    end
    interacao.merge(%w[header pergunta botao].index_with { |campo| limpar.call(interacao[campo]) }).merge('opcoes' => opcoes)
  end

  # O histórico do modelo com a versão em texto (`RichMessages.text_with_fallback`) das opções e do link que ESTE agente
  # mandou, para o turno seguinte saber o que ofereceu. `itens` e `messages` andam juntos (Responder#history). Na Lia
  # (`insurance_quote`) o histórico fica como está. Só conta a mensagem do robô-espelho de um vínculo DESTE agente
  # (`AgentInbox#agent_bot_id`), com a marca dele: texto de outro remetente não entra como fala do agente.
  def no_historico(itens, messages, agent:)
    return itens if agent.agent_type == 'insurance_quote'

    robos = ::Autonomia::Agents::AgentInbox.where(account_id: agent.account_id, autonomia_agent_id: agent.id)
                                           .pluck(:agent_bot_id).to_set
    itens.zip(messages).map do |item, message|
      oferecida?(message, agent, robos) ? item.merge(content: RichMessages.text_with_fallback(message, item[:content].to_s)) : item
    end
  end

  # A mensagem é opções ou link que ESTE agente mandou (a mesma regra do histórico)? Na Lia, nunca. `robos`: os de
  # `robos(agent)`, para quem chama mais de uma vez no turno não buscar de novo. Usado pelo Responder (PR-C).
  def oferta_do_agente?(message, agent:, robos: nil)
    return false if agent.agent_type == 'insurance_quote'

    oferecida?(message, agent, robos || robos(agent))
  end

  # O id da opção que o cliente tocou nesta mensagem, ou nil. A ÚNICA leitura do toque (PR-C): a Cloud grava
  # `content_attributes.selected_option` {id da opção oferecida, title} e a oferta em `in_reply_to` (WAHA e Híbrido
  # gravam a mesma chave depois do #1741). Só o id: quem lê confere contra a oferta, e o título vem dela, nunca do toque.
  # Id maior que o maior aceito pela Meta (o do botão, `RichMessages::Types::Options::BUTTONS[:id]`) não é de opção.
  def opcao_tocada(message)
    escolha = message&.content_attributes.to_h['selected_option']
    id = escolha['id'] if escolha.is_a?(Hash)
    id.to_s if id.present? && id.to_s.length <= RichMessages::Types::Options::BUTTONS[:id]
  end

  # A opção `id` na oferta, como o agente a escreveu ({ 'id', 'title' }), ou nil quando a oferta não tem esse id.
  def opcao_oferecida(oferta, id)
    opcoes = oferta.content_attributes.to_h.dig(RichMessages::KEY, 'options')
    opcao = Array(opcoes).find { |item| item.is_a?(Hash) && item['id'].to_s == id }
    { 'id' => opcao['id'].to_s, 'title' => opcao['title'] } if opcao
  end

  # Os robôs-espelho dos vínculos deste agente (`AgentInbox#agent_bot_id`).
  def robos(agent)
    ::Autonomia::Agents::AgentInbox.where(account_id: agent.account_id, autonomia_agent_id: agent.id).pluck(:agent_bot_id).to_set
  end

  def oferecida?(message, agent, robos)
    atributos = message&.content_attributes.to_h
    formato = atributos[RichMessages::KEY]
    message&.outgoing? && message.sender_type == 'AgentBot' && robos.include?(message.sender_id) &&
      atributos['autonomia_agent_id'] == agent.id && formato.is_a?(Hash) && TIPO_DO_FORMATO.value?(formato['type'])
  end

  # O `rich_message` (chaves em texto) da interação. O botão da lista sem texto do modelo, ou com um texto que o tipo
  # recusaria (a régua dele, `Options.fits?`), sai no idioma da conta: o texto do botão nunca derruba a lista inteira.
  def rich_message(interacao, locale:)
    return { 'type' => 'link_button', 'label' => interacao['rotulo'], 'url' => interacao['url'] } if interacao['tipo'] == 'link'
    return { 'type' => 'location_request' } if interacao['tipo'] == 'localizacao'

    opcoes = RichMessages::Types::Options
    botao = opcoes.fits?(interacao['botao'], opcoes::LIST_BUTTON_MAX) ? interacao['botao'] : I18n.t(BOTAO_PADRAO, locale: locale)
    { 'type' => 'options', 'header' => interacao['header'], 'button' => botao, 'options' => interacao['opcoes'].map(&:compact) }.compact
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

  # Sem nenhuma opção com título (`opcoes: []`, ou só itens vazios): nil sem `pergunta`, como se o modelo não tivesse
  # pedido; com ela, as opções vazias saem só em texto (o contrato do tipo recusa a lista vazia), e a pergunta fica.
  def opcoes(valor)
    lista = Array(valor['opcoes']).select { |opcao| opcao.is_a?(Hash) && opcao['titulo'].present? }.map do |opcao|
      { 'id' => opcao['id'].to_s, 'title' => opcao['titulo'].to_s, 'description' => opcao['descricao'].presence }
    end
    return if lista.empty? && valor['pergunta'].blank?

    { 'tipo' => 'opcoes', 'header' => valor['header'].presence, 'pergunta' => valor['pergunta'].to_s,
      'botao' => valor['botao'].presence, 'opcoes' => lista }
  end

  def link(valor, enderecos)
    endereco = Enderecos.normalizado(valor['url']) if valor.is_a?(Hash)
    url = Enderecos.completo(endereco) if endereco && enderecos.include?(endereco)
    return if url.nil?

    # O endereço conferido, normalizado (`Enderecos.completo`), vai ao botão e à versão em texto; o que o normalize
    # recusa é link recusado.
    { 'tipo' => 'link', 'rotulo' => valor['rotulo'].to_s, 'url' => url }
  end
end

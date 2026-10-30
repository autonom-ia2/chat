# #1428 (tema 6, parte 3, entrega B) — as PERGUNTAS DE PROVA do "Mudar conversando". SÓ NO PILOTO (Fase 2).
#
# Depois que um ajuste entra, o cartão do resultado sai na hora e a prova chega segundos depois (decisão do Rodrigo): o
# agente responde, como no Testar, a até 3 mensagens de cliente que o próprio Construtor escreveu no turno
# (`perguntas_de_prova`), e um juiz diz, por índice, se cada resposta mostra a mudança (JuizDaProva).
#
# A PROVA NUNCA MEXE EM NADA DE VERDADE: o Answerer roda em modo `prova`, sem ferramenta nenhuma (nem agenda, nem HTTP,
# nem especialista, nem busca na web). Sem `tools`, o ResponsesClient faz uma chamada só e nada é executado.
#
# O resultado vai para `state['prova']` da conversa: { status: pendente | pronta | indisponivel, versao_id, desde,
# perguntas: [{ pergunta, resposta, equipe }], ok, total }. Só grava se o ajuste ainda é o último e ainda vale (a mesma
# regra do Desfazer, Agent#conversa_desfazivel): depois de um Desfazer ou de outro ajuste, o resultado é descartado. A
# escrita mexe só na chave `prova`, guardada no próprio UPDATE pela versão do ajuste e pela marca de desfeito.
# A Lia (insurance_quote) fica fora.
class Autonomia::Agents::ProvaDoAjuste
  FEATURE = 'agente_prova_do_ajuste'.freeze
  FORA = %w[insurance_quote].freeze
  # Pendente há mais que isto, a prova não vem mais (o job morreu ou não rodou): a tela mostra "não consegui testar".
  VALIDADE_DO_PENDENTE = 3.minutes
  # Só falha da IA (provedor, JSON, rede) vira "indisponível"; o resto sobe para o rastreio do job.
  FALHAS_DA_IA = [Crm::Ai::ResponsesClient::Error, JSON::ParserError, *Crm::Ai::ResponsesClient::NETWORK_ERRORS,
                  OpenSSL::SSL::SSLError, Errno::EHOSTUNREACH, Errno::ENETUNREACH].freeze
  # A guarda da escrita, no próprio UPDATE: a prova pendente deste ajuste, que segue o último e não desfeito.
  AINDA_VALE = "state->'prova'->>'status' = 'pendente' AND state->'prova'->>'versao_id' = :versao " \
               "AND state->'ultimo_ajuste'->>'versao_id' = :versao " \
               "AND coalesce(state->'ultimo_ajuste'->>'desfeito', 'false') <> 'true'".freeze

  # O campo do schema do ajuste (AjustePorLista): na mesma chamada do Construtor, sem chamada a mais. Forense do t6d
  # (P1): a escola perguntou do "teste de nivelamento", que não está escrito em campo nenhum, e o agente respondeu a
  # mensagem fixa, que não mostra tom nenhum. Causa raiz (22/10): a prova rodava com o portão de confiança, que o
  # atendimento não tem; agora roda como o atendimento (Playground.como_no_atendimento?), sem ferramenta, com a base.
  # Série 2 do t6d anulada: "Qual é o nome da escola?" tem resposta quase igual antes e depois do pedido; em pedido de
  # forma, a mensagem puxa uma resposta em que a forma aparece.
  PERGUNTAS_DESCRIPTION =
    'Quando mudancas nao esta vazia: ate 3 mensagens curtas que um cliente de verdade mandaria, escritas como o cliente ' \
    'escreve, cada uma com o pedido (o texto de pedido em mudancas) que ela testa (ex.: pedido "preco passa para a ' \
    'equipe", mensagem "Quanto custa o seguro auto?"). A prova roda sem ferramenta, como no Testar: o agente responde ' \
    'pelo que esta escrito nos campos dele e pela base de conhecimento, quando ligada. Cada mensagem cria a situacao ' \
    'exata em que o pedido vale. Para um pedido de ' \
    'forma (tamanho, tom, tratamento, emoji, formato): 2 mensagens de tipos diferentes, um cumprimento e uma pergunta ' \
    'cuja resposta e um fato ESCRITO nos campos do agente (prefira o human_card, a saudacao e os guardrails; o fato ' \
    'presente la, nao so o nome do assunto), e a mensagem nao traz o fato: o cliente pergunta, o agente responde; ' \
    'em todo pedido de forma, cada mensagem puxa uma resposta em que a forma aparece, com ao menos uma frase dirigida ' \
    'ao cliente: pergunta de dado curto (um nome, um endereco) nao serve para pedido de forma, porque a resposta sai ' \
    'quase igual antes e depois do pedido (ex.: numa padaria, em vez de "Qual o endereco?", "Voces fazem bolo de ' \
    'aniversario por encomenda?"); para tamanho, uma delas pede algo que puxaria uma resposta longa; para tom ou ' \
    'tratamento, a mensagem nao traz pronta a forma pedida. Para o que fazer quando nao souber: algo que nao esta em ' \
    'nenhum campo do agente nem na base. Para uma regra com gatilho (um assunto, um pedido do cliente): uma mensagem ' \
    'com esse gatilho. Cada pedido com ao menos uma mensagem. Nunca cite, parafraseie nem resuma a instruction ou o ' \
    'scaffold. Vazia quando mudancas esta vazia.'.freeze
  PERGUNTA_DE_PROVA = {
    type: 'object', additionalProperties: false, required: %w[mensagem pedido],
    properties: { mensagem: { type: 'string', description: 'A mensagem do cliente.' },
                  pedido: { type: 'string', description: 'O pedido que ela testa, com o mesmo texto de pedido em mudancas.' } }
  }.freeze
  # Os campos do agente que o juiz lê para julgar (o que ele tem escrito e a forma).
  CAMPOS_PARA_O_JUIZ = %w[instruction tone greeting fallback_message handoff_rule guardrails].freeze
  PERGUNTAS_MAX = 3
  # Os trechos da base que a resposta usou vão ao juiz (revisão do t6d, ALTO 1), com teto de quantidade e de tamanho. O
  # teto do tamanho é o maior pedaço que a base grava (Config::CHUNK_PROFILES): um trecho inteiro nunca é cortado.
  TRECHOS_MAX = 3
  TRECHO_MAX_CHARS = [*Autonomia::Agents::Config::CHUNK_PROFILES.values, Autonomia::Agents::Config::DEFAULT_CHUNK_PROFILE]
                     .pluck(:max).max
  PERGUNTA_MAX_CHARS = 200

  # As perguntas que o Construtor escreveu: até 3, sem branco nem repetida, cada uma curta, com o pedido que testa (o
  # texto do pedido em `mudancas`; outro texto vira `pedido` nil, que conta como não declarado). Lê também o formato
  # antigo, só o texto, que fica sem a chave `pedido`.
  # -> [{ 'pergunta' => texto, 'pedido' => texto do pedido ou nil (só no formato de agora) }]
  def self.perguntas(parsed)
    pedidos = Autonomia::Agents::Builder::AjustePorLista.mudancas(parsed).pluck('pedido')
    lidas = Array(parsed['perguntas_de_prova']).filter_map { |item| pergunta_lida(item, pedidos) }
    lidas.uniq { |item| item['pergunta'] }.first(PERGUNTAS_MAX)
  end

  def self.pergunta_lida(item, pedidos)
    texto, pedido = item.is_a?(Hash) ? item.values_at('mensagem', 'pedido') : [item, nil]
    return unless texto.is_a?(String) && texto.strip.present?

    lida = { 'pergunta' => texto.strip.truncate(PERGUNTA_MAX_CHARS) }
    item.is_a?(Hash) ? lida.merge('pedido' => pedido_da_lista(pedido, pedidos)) : lida
  end

  # O texto do pedido em `mudancas` que a mensagem diz testar (o ponto final não conta); outro texto, nenhum.
  def self.pedido_da_lista(pedido, pedidos)
    alvo = Autonomia::Agents::ResultadoDoAjuste.sem_ponto(pedido)
    return if alvo.blank?

    pedidos.find { |texto| Autonomia::Agents::ResultadoDoAjuste.sem_ponto(texto) == alvo }
  end
  private_class_method :pergunta_lida, :pedido_da_lista

  # O estado inicial, gravado junto com o fechamento do turno aplicado. nil sem perguntas ou fora da prova. Lê o formato
  # antigo (só o texto), gravado num ajuste em curso antes do deploy.
  def self.pendente(agent, dados)
    perguntas = Array(dados['perguntas_de_prova']).filter_map { |item| pergunta_pendente(item) }
    return if perguntas.empty? || agent.nil? || FORA.include?(agent.agent_type)

    { 'status' => 'pendente', 'versao_id' => dados.dig('correcao', 'versao_id') || dados['versao_id'],
      'desde' => Time.current.iso8601, 'perguntas' => perguntas }
  end

  # Um item gravado: o formato de agora ({pergunta, pedido}), o do modelo ({mensagem, pedido}) ou o antigo (só o texto,
  # ou {pergunta} sem a chave `pedido`, que continua sem ela). Sem texto, fica fora.
  def self.pergunta_pendente(item)
    texto = item.is_a?(Hash) ? item['pergunta'] || item['mensagem'] : item
    return unless texto.is_a?(String) && texto.strip.present?

    lida = { 'pergunta' => texto }
    item.is_a?(Hash) && item.key?('pedido') ? lida.merge('pedido' => item['pedido'].presence) : lida
  end
  private_class_method :pergunta_pendente

  def initialize(thread, versao_id)
    @thread = thread
    @versao_id = versao_id
  end

  # Confere antes de cada pergunta e antes do juiz: depois de um Desfazer, para na próxima; repetido depois de pronta,
  # não gasta nada.
  def rodar!
    return unless vigente?

    itens = []
    Array(@thread.state.dig('prova', 'perguntas')).each do |pergunta|
      return false unless vigente?

      resposta = responder(pergunta['pergunta'])
      return gravar!('status' => 'indisponivel') if resposta.nil?

      itens << resposta.merge(pergunta.slice('pergunta', 'pedido'))
    end
    julgar_e_gravar!(itens) if vigente?
  rescue *FALHAS_DA_IA => e
    Rails.logger.warn("[autonomia][prova_do_ajuste] falhou thread=#{@thread.id} #{e.class}")
    gravar!('status' => 'indisponivel')
  end

  private

  # O placar conta só as perguntas que tocam a mudança (`total` 0: nenhuma testou, a tela não mostra ✓), pelo veredito
  # da pergunta que o juiz deriva dos testes (um nao em qualquer pedido: a pergunta é nao). `completa`: cada pedido do
  # dono teve ao menos um teste; sem isso, a tela não mostra ✓.
  def julgar_e_gravar!(itens)
    pedidos = pedidos_aplicados
    veredito = Autonomia::Agents::JuizDaProva.new(account: @thread.account).julgar(pedidos: pedidos, itens: itens,
                                                                                   agente: campos_para_o_juiz)
    return gravar!('status' => 'indisponivel') if veredito.nil?

    notas = veredito.pluck('veredito')
    gravar!('status' => 'pronta', 'ok' => notas.count('ok'), 'total' => notas.count { |nota| nota != 'nao_testa' },
            'completa' => completa?(pedidos, veredito, itens),
            'perguntas' => itens.zip(veredito).map { |item, nota| item.merge(nota) })
  end

  # Cada posição da lista de pedidos (a partir de 0) aparece em algum teste do juiz: uma resposta pode testar várias, e
  # um pedido testado com nao conta como testado (o placar `ok` de `total` mostra a falha). Com um pedido só, uma
  # pergunta que o testa basta. Antes do juiz: cada pedido tem uma mensagem que o declara (revisão do t6d, MÉDIO 2), e
  # nenhum item da correção saiu por texto de pedido fora da lista (MÉDIO 1).
  def completa?(pedidos, veredito, itens)
    testados = veredito.flat_map { |nota| Array(nota['testes']) }.pluck('pedido')
    pedidos.any? && declarados?(pedidos, itens) && sem_descarte? &&
      pedidos.each_index.all? { |posicao| testados.include?(posicao) }
  end

  # Só quando TODAS as mensagens vieram no formato antigo (só o texto, sem a chave `pedido`) não há o que conferir.
  # Uma mensagem cujo pedido não bateu com a lista (`pedido` nil) conta como não declarada (revisão 2, MÉDIO 1).
  def declarados?(pedidos, itens)
    declaradas = itens.select { |item| item.key?('pedido') }
    return true if declaradas.empty?
    return false if declaradas.any? { |item| item['pedido'].nil? }

    textos = declaradas.map { |item| Autonomia::Agents::ResultadoDoAjuste.sem_ponto(item['pedido']) }
    pedidos.all? { |pedido| textos.include?(pedido['pedido']) }
  end

  def sem_descarte?
    @thread.state.dig('ultimo_ajuste', 'conferencia', 'itens_descartados').to_i.zero?
  end

  # A resposta do agente, pelo mesmo caminho do Testar, sem ferramenta. nil quando a IA falhou. `equipe`: o agente
  # avisou que chamaria alguém da equipe (o sinal da instrução, com a fala dele).
  def responder(pergunta)
    resultado = Autonomia::Agents::Answerer.new(agent: @thread.agent, query: pergunta, feature: FEATURE, prova: true,
                                                trust_instruction: Autonomia::Agents::Playground.como_no_atendimento?(@thread.agent)).answer
    texto = resultado.reply.to_s.strip.presence
    equipe = resultado.handoff[:should] == true
    return if resultado.error.present? || (texto.nil? && !equipe)

    trechos = trechos_usados(resultado)
    { 'resposta' => texto, 'equipe' => equipe }.merge(trechos.any? ? { 'trechos' => trechos } : {})
  end

  # Os trechos da base que a resposta usou (o conteúdo do próprio dono), com teto: o juiz conta o fato deles como sabido.
  def trechos_usados(resultado)
    Array(resultado.used_knowledge).filter_map { |trecho| trecho[:content].to_s.strip.presence }
                                   .first(TRECHOS_MAX).map { |texto| texto.truncate(TRECHO_MAX_CHARS) }
  end

  # O que o agente tem escrito, para o juiz julgar "quando não souber" e a forma (forense do t6d, P2).
  def campos_para_o_juiz
    Autonomia::Agents::Builder::AjustePorLista.retrato(@thread.agent).slice(*CAMPOS_PARA_O_JUIZ)
  end

  # O que entrou neste ajuste: os pedidos do dono pelos MESMOS grupos do cartão (ResultadoDoAjuste#grupos_pedidos), só
  # os aplicados, numerados a partir de 1 para o juiz, nas palavras que o Construtor escreveu (`pedido` e os `resumo`
  # dos campos de cada pedido).
  def pedidos_aplicados
    conferencia = @thread.state.dig('ultimo_ajuste', 'conferencia').to_h
    grupos = Autonomia::Agents::ResultadoDoAjuste.new(nil, conferencia).grupos_aplicados
    grupos.each_with_index.map do |grupo, posicao|
      { 'numero' => posicao + 1, 'pedido' => Autonomia::Agents::ResultadoDoAjuste.sem_ponto(grupo.first['pedido']),
        'o_que_mudou' => grupo.pluck('resumo').uniq }
    end
  end

  # A prova ainda está pendente, e o ajuste dela ainda é o último da conversa e vale (não desfeito, o agente com os campos
  # que ele gravou).
  def vigente?
    @thread.reload
    estado = @thread.state.to_h
    prova = estado['prova'].to_h
    @thread.agent.present? && prova['status'] == 'pendente' && !vencida?(prova) && prova['versao_id'] == @versao_id &&
      estado.dig('ultimo_ajuste', 'versao_id') == @versao_id && @thread.agent.conversa_desfazivel&.id == @thread.id
  end

  # Pendente há mais que a validade: a tela já mostra "não consegui testar" e o job não gasta mais nada (cena W3).
  def vencida?(prova)
    desde = Time.zone.parse(prova['desde'].to_s)
    desde.nil? || desde.before?(VALIDADE_DO_PENDENTE.ago)
  end

  # Só a chave `prova`, e só se o ajuste continua o mesmo e não desfeito no instante da escrita.
  def gravar!(resultado)
    return false unless vigente?

    prova = @thread.state['prova'].merge(resultado)
    Autonomia::Agents::BuildThread.where(id: @thread.id).where(AINDA_VALE, versao: @versao_id.to_s)
                                  .update_all(["state = jsonb_set(state, '{prova}', ?::jsonb)", prova.to_json]) == 1 # rubocop:disable Rails/SkipsModelValidations
  end
end

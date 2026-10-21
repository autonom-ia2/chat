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

  # O campo do schema do ajuste (AjustePorLista): na mesma chamada do Construtor, sem chamada a mais.
  PERGUNTAS_DESCRIPTION =
    'Quando mudancas nao esta vazia: ate 3 mensagens curtas que um cliente de verdade mandaria, escritas como o cliente ' \
    'escreve, que facam o agente mostrar a mudanca pedida (ex.: pedido "preco passa para a equipe", mensagem "Quanto ' \
    'custa o seguro auto?"). Cada mensagem cria a situacao exata em que o pedido vale: para tom, tamanho ou formato, ' \
    'uma pergunta que o agente responde com o que ja sabe; para o que fazer quando nao souber, algo claramente fora do ' \
    'que o agente sabe; para uma regra com gatilho (um assunto, um pedido do cliente), uma mensagem com esse gatilho. ' \
    'Cada uma cobre um pedido diferente quando houver mais de um. Nunca cite, parafraseie nem ' \
    'resuma a instruction ou o scaffold. Vazia quando mudancas esta vazia.'.freeze
  PERGUNTAS_MAX = 3
  PERGUNTA_MAX_CHARS = 200

  # As perguntas que o Construtor escreveu: até 3, só texto, sem branco nem repetida, cada uma curta.
  def self.perguntas(parsed)
    textos = Array(parsed['perguntas_de_prova']).select { |texto| texto.is_a?(String) }
                                                .map { |texto| texto.strip.truncate(PERGUNTA_MAX_CHARS) }
    textos.compact_blank.uniq.first(PERGUNTAS_MAX)
  end

  # O estado inicial, gravado junto com o fechamento do turno aplicado. nil sem perguntas ou fora da prova.
  def self.pendente(agent, dados)
    perguntas = Array(dados['perguntas_de_prova'])
    return if perguntas.empty? || agent.nil? || FORA.include?(agent.agent_type)

    { 'status' => 'pendente', 'versao_id' => dados.dig('correcao', 'versao_id') || dados['versao_id'],
      'desde' => Time.current.iso8601, 'perguntas' => perguntas.map { |pergunta| { 'pergunta' => pergunta } } }
  end

  def initialize(thread, versao_id)
    @thread = thread
    @versao_id = versao_id
  end

  # Confere antes de cada pergunta e antes do juiz: depois de um Desfazer, para na próxima; repetido depois de pronta,
  # não gasta nada.
  def rodar!
    return unless vigente?

    itens = []
    Array(@thread.state.dig('prova', 'perguntas')).pluck('pergunta').each do |pergunta|
      return false unless vigente?

      resposta = responder(pergunta)
      return gravar!('status' => 'indisponivel') if resposta.nil?

      itens << resposta.merge('pergunta' => pergunta)
    end
    julgar_e_gravar!(itens) if vigente?
  rescue *FALHAS_DA_IA => e
    Rails.logger.warn("[autonomia][prova_do_ajuste] falhou thread=#{@thread.id} #{e.class}")
    gravar!('status' => 'indisponivel')
  end

  private

  # O placar conta só as perguntas que tocam a mudança (`total` 0: nenhuma testou, a tela não mostra ✓). `completa`: cada
  # pedido do dono teve ao menos uma pergunta que o testou (o juiz diz qual); sem isso, a tela não mostra ✓.
  def julgar_e_gravar!(itens)
    pedidos = pedidos_aplicados
    veredito = Autonomia::Agents::JuizDaProva.new(account: @thread.account).julgar(pedidos: pedidos, itens: itens)
    return gravar!('status' => 'indisponivel') if veredito.nil?

    notas = veredito.pluck('veredito')
    gravar!('status' => 'pronta', 'ok' => notas.count('ok'), 'total' => notas.count { |nota| nota != 'nao_testa' },
            'completa' => completa?(pedidos, veredito),
            'perguntas' => itens.zip(veredito).map { |item, nota| item.merge(nota) })
  end

  def completa?(pedidos, veredito)
    testados = veredito.pluck('pedido').compact
    testados.any? && pedidos.pluck('numero').all? { |numero| testados.include?(numero) }
  end

  # A resposta do agente, pelo mesmo caminho do Testar, sem ferramenta. nil quando a IA falhou. `equipe`: o agente
  # passaria a conversa para a equipe (a tela mostra isso quando não há texto).
  def responder(pergunta)
    resultado = Autonomia::Agents::Answerer.new(agent: @thread.agent, query: pergunta, feature: FEATURE, prova: true).answer
    texto = resultado.reply.to_s.strip.presence
    equipe = resultado.handoff[:should] == true
    return if resultado.error.present? || (texto.nil? && !equipe)

    { 'resposta' => texto, 'equipe' => equipe }
  end

  # O que entrou neste ajuste, um item numerado por pedido do dono, nas palavras que o Construtor escreveu para ele
  # (`pedido` e os `resumo` dos campos desse pedido).
  def pedidos_aplicados
    itens = Array(@thread.state.dig('ultimo_ajuste', 'conferencia', 'itens'))
    itens.reject { |item| item['atendido'] == false || item['pedido_pelo_dono'] == false }
         .group_by { |item| item['pedido'] }.each_with_index
         .map { |(pedido, grupo), numero| { 'numero' => numero, 'pedido' => pedido, 'o_que_mudou' => grupo.pluck('resumo').uniq } }
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

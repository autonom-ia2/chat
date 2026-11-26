# O AGENTE LÊ A MENSAGEM QUE CHEGA NO MEIO DO TURNO (#3225, flag `agente_le_no_meio_do_turno`). O cliente que fala picado
# ("França, 15 a 20/01, 40 anos" e, enquanto o agente cota, "Conhece lá?") recebe uma resposta só, com a cotação já feita.
# Sem isto, o turno da primeira mensagem era superado na hora de postar e o da segunda refazia tudo (outra cotação, outro
# PDF). É o que o Guia já faz (`Answerer#mensagens_novas_da_pessoa`), agora no atendimento.
#
# QUEM LÊ: o turno de uma mensagem do cliente (`Responder` com âncora), de agente que não é a Lia, com a espera da fala
# (P1) e a fila (P2) ligadas (`ligada?`). A fila segura o turno da mensagem nova enquanto este fala; a rajada (P1) garante
# que nada se perde quando este turno não posta. O turno da passagem e o de evento não têm âncora e não leem.
#
# O QUE LÊ: as mensagens do cliente com id maior que o `piso` (a âncora e a rajada que já foi na pergunta), em ordem, até
# LIMITE por leitura. Cada uma passa pelo texto do Responder (`Responder#texto_no_meio_do_turno`, que os prepends do WAHA
# completam); a que não tem texto legível (apagada, visualização única, voto retirado, toque em opção, imagem, documento)
# PARA a leitura ali, para não furar a ordem, e segue o caminho de hoje.
#
# ONDE FICA O QUE FOI LIDO: em memória, no `Delivery` do turno (só os ids), que a hora de postar e a ferramenta que
# confere o turno (`ReplyJob.turno_superado?`) enxergam. Ao postar, a resposta grava os ids em `CHAVE`, na mesma transação
# do post: é por ela que o turno da mensagem lida sabe que já foi respondido junto (`respondida_junto?`). Sem Redis.
#
# QUANTO LÊ: no máximo MAX_VOLTAS voltas a mais por turno (cada uma, uma ida com ferramenta e o fechamento). No teto, ou
# com o relógio do laço esgotado, a leitura para: o que chegar depois fica sem ler, o turno é superado na hora de postar
# e o turno novo responde tudo pela rajada (o caminho de hoje).
#
# Quem decide parar, mudar ou seguir é o modelo, pelo aviso; aqui nada interpreta o que o cliente escreveu.
class Autonomia::Agents::Operate::LeituraNoTurno
  FLAG = 'agente_le_no_meio_do_turno'.freeze
  CHAVE = 'autonomia_lidas_no_turno'.freeze
  # A etiqueta do custo das idas a mais na Gestão IA (o turno de sempre segue `agente_resposta`).
  FEATURE_DA_VOLTA = 'agente_resposta_volta'.freeze
  MAX_VOLTAS = 2
  LIMITE = 10
  # A Lia fica fora, pelo tipo (regra da casa: o comportamento dela não muda).
  TIPO_FORA = 'insurance_quote'.freeze
  # QUANTO O TURNO QUE LÊ PODE DURAR, para a fila (`EsperaDaFala.prazo_da_fila`) do turno de uma mensagem que ele pode
  # ter lido. Sem a parcela da Lia (ela não lê): o relógio do laço mais longo de quem lê (o de sempre, o das prontas ou
  # o do principal com ajudante), mais uma ida de cada vez até o fim, a de antes da 1ª leitura e as duas de cada volta
  # (a rodada e o fechamento), cada uma até REQUEST_TIMEOUT, mais a cadeia de pedaços inteira. Passou disto, o turno que
  # falava morreu sem soltar a fala (OOM, deploy): a fila desiste e a mensagem é respondida.
  PRAZO_DE_QUEM_LE = ([::Crm::Ai::ResponsesClient::MAX_SEGUNDOS_DE_FERRAMENTA, ::Autonomia::FerramentasProntas::PRAZO_DAS_RODADAS,
                       ::Autonomia::Agents::Ajudantes::PRAZO_DA_RESPOSTA].max +
                      (((2 * MAX_VOLTAS) + 1) * ::Crm::Ai::ResponsesClient::REQUEST_TIMEOUT) +
                      (::Autonomia::Agents::Config::HUMANIZE[:max_total_delay_ms] / 1000)).seconds
  AVISO_ANTES_DE_ENVIAR = 'A resposta acima ainda não foi enviada ao cliente. Enquanto você a preparava, ele mandou ' \
                          '%<o_que>s. Escreva uma resposta só, que sirva para tudo o que ele disse. O que as ferramentas ' \
                          'já trouxeram continua valendo: chame de novo só se o pedido mudou.'.freeze

  class << self
    # A chave vale para este agente nesta conversa? Desligada, nenhum caminho novo roda.
    def ligada?(agent, conversation)
      return false if agent.nil? || conversation.nil? || agent.agent_type == TIPO_FORA

      paridade = ::Autonomia::Agents::ParidadeDaConversa
      conversation.account.feature_enabled?(FLAG) && paridade.em_fila?(agent, conversation.inbox) &&
        paridade.espera_a_fala?(agent, conversation.inbox)
    end

    # A mensagem mais nova do cliente (`pendente`, a da marca do debounce) foi lida pelo turno (`lidas`) do `agent`, a
    # chave segue ligada e ela ainda não tem resposta própria: o turno que leu responde por ela. Sem lidas, nem consulta o
    # banco. Chave desligada no meio do turno: não cobre (o turno que leu fica superado e a mensagem nova responde).
    def cobre?(conversation, pendente, lidas, agent)
      ids = Array(lidas).map(&:to_s)
      return false if pendente.blank? || ids.exclude?(pendente.to_s)
      return false unless ligada?(agent, conversation)

      !respondida_propria?(conversation, pendente)
    end

    # Com a chave, uma resposta do `agent` na conversa leu esta mensagem do cliente no meio do turno dela (grava os ids em
    # CHAVE). Sem a chave, nem consulta o banco.
    def respondida_junto?(conversation, message_id, agent)
      return false if message_id.blank? || !ligada?(agent, conversation)

      respostas_depois(conversation, message_id, CHAVE).any? do |resposta|
        atributos = resposta.content_attributes.to_h
        atributos['autonomia_agent_id'].to_s == agent.id.to_s && Array(atributos[CHAVE]).map(&:to_s).include?(message_id.to_s)
      end
    end

    # A cadeia de pedaços de um turno que leu (as lidas no meta) parou: o mesmo rastro do silêncio do Responder.
    def parou_nos_pedacos(conversation:, msg:, meta:, motivo:, pedaco:)
      leitura = do_meta(meta)
      return if leitura.empty? || %i[ja_postado sem_pedaco].include?(motivo)

      ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(:leitura_no_silencio, conversation_id: conversation.id, msg: msg,
                                                                                      motivo: motivo, pedaco: pedaco,
                                                                                      lidas: leitura['lidas_no_turno'].size,
                                                                                      voltas: leitura['voltas'])
    end

    # O turno desta mensagem já postou a resposta dele (`autonomia_reply_to_message_id`).
    def respondida_propria?(conversation, message_id)
      respostas_depois(conversation, message_id, 'autonomia_reply_to_message_id').any? do |resposta|
        resposta.content_attributes.to_h['autonomia_reply_to_message_id'].to_s == message_id.to_s
      end
    end

    # O que a resposta grava ao postar. {} sem lidas.
    def marca(lidas)
      ids = Array(lidas).select { |id| id.is_a?(Integer) }
      ids.empty? ? {} : { CHAVE => ids }
    end

    # Do meta dos pedaços para o evento `replied` (só ids e o número de voltas). {} sem a leitura.
    def do_meta(meta)
      return {} unless meta.to_h.key?('lidas_no_turno')

      { 'lidas_no_turno' => Array(meta['lidas_no_turno']).select { |id| id.is_a?(Integer) }, 'voltas' => meta['voltas'].to_i }
    end

    private

    # Prefiltro pela chave no texto da coluna e confirmação no hash, em Ruby: o mesmo molde do
    # `ChunkedDeliveryJob#chunk_message` (a coluna json guarda uma string JSON; nada de adivinhar o escape).
    def respostas_depois(conversation, message_id, chave)
      conversation.messages.outgoing.where(sender_type: 'AgentBot').where('id > ?', message_id.to_i)
                  .where('content_attributes::text LIKE ?', "%#{chave}%")
    end
  end

  attr_reader :voltas

  # `ancora`: a mensagem do turno. `rajada`: os ids que já foram na pergunta; os maiores que a âncora já contam como lidos
  # (chegaram depois do gatilho, antes de o turno montar a pergunta). O bloco dá o texto de uma mensagem, ou nil quando ela
  # não é legível.
  def initialize(conversation:, agent:, delivery:, ancora:, rajada: [], &texto)
    @conversation = conversation
    @agent = agent
    @delivery = delivery
    @ancora = ancora.to_i
    @texto = texto
    @voltas = 0
    ids = Array(rajada).map(&:to_i)
    @piso = [@ancora, *ids].max
    @criada_em = Time.current
    @delivery.ler_no_turno(ids.select { |id| id > @ancora })
  end

  def lidas = @delivery.lidas_no_turno

  def feature_da_volta = FEATURE_DA_VOLTA

  # Na rodada de ferramentas: o que chegou entra depois das saídas, como fala do cliente, com o aviso do Guia. [] sem nada.
  def na_rodada(esgotado: false)
    novas = com_as_guardadas(ler(:rodada, esgotado))
    return [] if novas.empty?

    [mensagem('developer', ::Autonomia::Agents::Answerer::AVISO_DE_MENSAGEM_NOVA), *falas(novas)]
  end

  # Antes de enviar: com algo novo, o rascunho volta como fala do agente (só o texto, nunca os itens de raciocínio), o
  # aviso de que ele não foi enviado e o que chegou. [] sem nada.
  def antes_de_enviar(rascunho, esgotado: false)
    novas = com_as_guardadas(ler(:antes_de_enviar, esgotado))
    return [] if novas.empty?

    o_que = novas.size == 1 ? 'a mensagem a seguir' : 'as mensagens a seguir'
    [mensagem('assistant', rascunho.to_s), mensagem('developer', format(AVISO_ANTES_DE_ENVIAR, o_que: o_que)), *falas(novas)]
  end

  # A ferramenta que confere o turno antes de agir (`cotar_seguro_viagem`) lê o que chegou, para não recusar o trabalho
  # que este turno vai entregar cobrindo a mensagem nova. O que ela leu já conta como lido e vai ao modelo na próxima
  # leitura do laço (`na_rodada` ou `antes_de_enviar`), mesmo com o relógio ou o teto: lida, a mensagem não tem outro
  # turno que a responda.
  def ler_agora
    @guardadas = Array(@guardadas) + ler(:ferramenta, false)
    nil
  end

  def contar_volta!(etapa)
    @voltas += 1
    rastrear(:volta_do_turno, volta: @voltas, etapa: etapa)
  end

  # Para o evento `replied` e o meta dos pedaços.
  def metadata
    { 'lidas_no_turno' => lidas, 'voltas' => @voltas }
  end

  # O silêncio do turno que leu (ou tentou ler). No `turno_superado`, de quem foi a mensagem que superou e quantos ms
  # depois da última leitura ela chegou (negativo: chegou antes e não foi lida).
  def no_silencio(motivo)
    campos = { motivo: motivo, lidas: lidas.size, voltas: @voltas }
    rastrear(:leitura_no_silencio, **campos, **(motivo.to_s == 'turno_superado' ? quem_superou : {}))
  end

  private

  def ler(etapa, esgotado)
    return [] if @parada

    candidatas = proximas
    return parar(:relogio, candidatas.first) if esgotado && candidatas.any?
    return parar(:teto, candidatas.first) if @voltas >= MAX_VOLTAS && candidatas.any?

    @ultima_leitura_em = Time.current
    em_ordem(candidatas, etapa)
  end

  def com_as_guardadas(novas)
    guardadas = Array(@guardadas)
    @guardadas = []
    guardadas + novas
  end

  # Lê na ordem e para na primeira ilegível. -> os textos lidos.
  def em_ordem(candidatas, etapa)
    novas = []
    candidatas.each do |recebida|
      texto = texto_de(recebida)
      if texto.blank?
        parar(:ilegivel, recebida)
        break
      end

      novas << texto
      marcar_lida(recebida, etapa)
    end
    novas
  end

  def proximas
    @conversation.messages.chat.incoming.where('id > ?', @piso).reorder(:id).limit(LIMITE).to_a
  end

  # A falha esperada de mídia (a transcrição, o download) já chega aqui como nil: o `MessageMedia` a registra e devolve
  # sem transcrição, e a mensagem é ilegível. A citação (`Responder#quoted_context`) também resolve a dela. Nada é
  # resgatado aqui: erro de programação sobe e derruba o turno, que o Responder registra (`responder_failed`), em vez de
  # parar a leitura calado.
  def texto_de(recebida)
    @texto.call(recebida)
  end

  def marcar_lida(recebida, etapa)
    @piso = recebida.id
    @delivery.ler_no_turno([recebida.id])
    rastrear(:mensagem_lida_no_turno, lida: recebida.id, etapa: etapa)
  end

  # A leitura para de vez neste turno. -> []
  def parar(motivo, recebida)
    @parada = true
    rastrear(:leitura_parou, lida: recebida.id, motivo: motivo)
    []
  end

  def quem_superou
    pendente = @conversation.additional_attributes.to_h.dig(::Autonomia::Agents::Operate::ReplyJob::DEBOUNCE_KEY, 'pending_message_id')
    recebida = pendente.present? ? @conversation.messages.find_by(id: pendente) : nil
    return {} if recebida.nil?

    segundos = recebida.created_at - (@ultima_leitura_em || @criada_em)
    { superou: recebida.id, depois_da_leitura: segundos.positive?, ms: (segundos * 1000).round }
  end

  def falas(textos)
    textos.map { |texto| mensagem('user', ::Autonomia::Agents::Config.truncate_text(texto, ::Autonomia::Agents::Config::MAX_HISTORY_ITEM_CHARS)) }
  end

  def mensagem(role, texto) = ::Autonomia::Agents::PromptParts::Mensagem.montar(role, texto)

  def rastrear(evento, **campos)
    ::Autonomia::Agents::Operate::TelemetriaDoTurno.registrar(evento, conversation_id: @conversation.id, agent: @agent.id,
                                                                      msg: @ancora, **campos)
  end
end

# A CONSULTA HTTP EM SEGUNDO PLANO, DO LADO DO TURNO (#1430, desenho D aprovado pelo Rodrigo).
#
# Com a flag `agente_ferramenta_em_segundo_plano` e uma conversa, TODA chamada da ferramenta HTTP sai do turno: abre
# uma execução `running` e enfileira o `HttpAssincronaJob` na fila `agent_tools` na hora. O turno espera por ela até
# `ESPERA_DO_TURNO`, contados do pré-disparo da RODADA (a janela mora no `Delivery`; cada rodada abre a sua, e as
# chamadas da mesma rodada esperam juntas), lendo só o estado da linha.
#   - Chegou na janela: o modelo lê o mesmo texto do síncrono (a resposta com o teto, ou a recusa HTTP, registrada).
#   - Não chegou: o modelo lê `EM_ANDAMENTO`, e o resultado chega por evento (`consulta_concluida`/`consulta_falhou`)
#     num turno novo.
# A decisão é pelo tempo REAL da resposta, não pelo configurado: o único limite é o `timeout_seconds` da ferramenta.
#
# QUEM ENTREGA é decidido por uma marca só na linha (`ToolRun::ConsultaHttp::ENTREGA`), por compare-and-set: o turno
# marca `entregue_no_turno` ou `desistiu_do_turno`, e a desistência só vale sem resultado gravado. O job só dispara o
# evento com a desistência. Na corrida, a entrega acontece uma vez.
#
# REAPROVEITAR, NUNCA CHAMAR DUAS VEZES O MESMO PEDIDO:
#   - a mesma Idempotency-Key (o turno refeito, a mesma chamada de novo) reusa a execução que roda ou que concluiu com
#     2xx; a que falhou não é reusada: o turno chama de novo com a mesma chave, como no síncrono;
#   - o mesmo pedido numa mensagem nova (outra chave) se pendura na execução da conversa que já chamou o sistema de
#     fora; a que ainda não chamou é trocada pela nova (`superar_sem_chamada!`).
#
# Sem conversa (Testar, playground, Copiloto), sem a flag ou no turno de um evento, nada daqui roda: a ferramenta é
# síncrona, como no #2426.
class Autonomia::Agents::Tools::ConsultaNoTurno
  ToolRun = ::Autonomia::Agents::ToolRun
  Chave = ::Autonomia::Agents::Tools::ChaveDeIdempotencia
  Erro = ::Autonomia::Agents::Tools::HttpExecutor::Error

  FLAG = 'agente_ferramenta_em_segundo_plano'.freeze
  ESPERA_DO_TURNO = 8
  # De quanto em quanto tempo o turno lê o estado da linha (só a coluna).
  INTERVALO = 0.25
  EM_ANDAMENTO = 'Consulta em andamento. Avise o cliente que você está consultando e que responde assim que tiver o ' \
                 'resultado.'.freeze
  # A execução terminou, e quem fala do resultado é o evento (o turno que a pediu desistiu da janela).
  JA_INFORMADO = 'Esta consulta já terminou, e o resultado foi (ou está sendo) dado ao cliente numa mensagem à parte. ' \
                 'Não repita o resultado; siga a conversa.'.freeze
  # O código da recusa quando a consulta nem chegou a sair (infraestrutura): o modelo lê `tool_execution_error`.
  NAO_DISPAROU = 'tool_execution_error: consulta_nao_disparou'.freeze
  FIM = %w[done failed].freeze

  # O que o turno guarda de cada chamada disparada: a execução e a janela da rodada, ou a falha do disparo.
  Disparo = Struct.new(:run, :janela, :falhou, keyword_init: true)

  # Com conversa (o `Delivery` do turno, também o do principal quando quem chama é o ajudante) e a flag da conta. O turno
  # de um evento (`ResponderAoEvento`) roda síncrono: uma consulta aberta nele terminaria em outro evento, e o laço
  # evento -> consulta -> evento não teria fim.
  def self.aplica?(tool, turno)
    return false unless turno.respond_to?(:conversation) && turno.conversation.present?
    return false if turno.try(:turno_de_evento?)

    ligada?(tool.account)
  end

  # O bit da flag entra no config/features.yml pela Orquestração (ext_2, posição 23). Enquanto ele não está lá, o
  # `feature_<flag>?` não existe e a conta segue o caminho síncrono do #2426, em vez de levantar em toda chamada HTTP. O
  # aviso sai uma vez por processo: a flag não liga sem o bit, e ninguém precisa descobrir isso lendo código.
  def self.ligada?(account)
    return account.feature_enabled?(FLAG) if account.respond_to?("feature_#{FLAG}?")

    avisar_sem_bit
    false
  end

  def self.avisar_sem_bit
    return if @avisou_sem_bit

    @avisou_sem_bit = true
    Rails.logger.warn("[autonomia][tool][consulta] a flag #{FLAG} não tem bit no config/features.yml: a consulta HTTP segue síncrona")
  end

  # O pré-disparo de uma rodada (o `Answerer` e o `Specialists::Runner`, uma vez por rodada) abre a janela dela.
  def self.nova_rodada(turno)
    turno.abrir_janela_das_consultas(agora, ESPERA_DO_TURNO) if turno.respond_to?(:abrir_janela_das_consultas)
  end

  # Os dois relógios da espera, em métodos de classe para o spec dublar: o monotônico e a pausa entre leituras.
  def self.agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.pausar(segundos)
    sleep(segundos)
  end

  # `agente`: quem fala nesta conversa (o principal). A execução é dele: é ele quem fala do resultado no evento.
  # `chamada`: o `call_id` do modelo, que liga o pré-disparo à execução da mesma chamada.
  # Levanta `HttpExecutor::ValorRecusado` quando um valor não converte: o `Bound` recusa como no síncrono.
  def initialize(tool:, agente:, turno:, args:, chamada: nil)
    @tool = tool
    @agente = agente
    @turno = turno
    @chamada = chamada.presence
    @params = ::Autonomia::Agents::Tools::ParamsTipados.converter(args.to_h.deep_stringify_keys, tool.param_schema)
    @pedido = Chave.pedido(tool, turno, @params)
  end

  # O pré-disparo (`pre_disparo: true`, com a ocorrência reservada na rodada) ou o disparo da própria execução. Erro de
  # infraestrutura (banco, Redis no enfileiramento) não derruba o turno: fica registrado, e a execução recusa.
  # -> o `Disparo`.
  def disparar(pre_disparo: false)
    ocorrencia = pre_disparo ? @turno.reservar_ocorrencia(@pedido) : @turno.ocorrencia(@pedido)
    @chave = Chave.com_ocorrencia(@pedido, ocorrencia)
    @ocorrencia = ocorrencia
    @turno.consultas[identidade] ||= Disparo.new(run: reaproveitada || abrir, janela: janela)
  rescue StandardError => e
    registrar_falha('disparo', e)
    @turno.consultas[identidade] = Disparo.new(falhou: true)
  end

  # -> o texto que o modelo lê. Uma falha que chega na janela levanta `HttpExecutor::Error`, como o síncrono: o `Bound`
  # a registra e devolve a mesma recusa. O erro de infraestrutura no meio da espera (o banco) vira a recusa nomeada, com
  # o registro no log: o turno não morre por ele.
  def resultado
    disparo = tomar_disparo
    raise Erro, NAO_DISPAROU if disparo.falhou

    esperar(disparo)
  rescue Erro
    raise
  rescue StandardError => e
    registrar_falha('espera', e)
    raise Erro, NAO_DISPAROU
  end

  private

  def esperar(disparo)
    run = disparo.run.reload
    return ja_com_o_evento(run) if run.entrega == ToolRun::DESISTIU_DO_TURNO

    status = aguardar(run, disparo.janela)
    return entregar(run) if FIM.include?(status)
    return desistir(run, disparo.janela) if status == 'running'
    return EM_ANDAMENTO if status == 'superseded'

    raise Erro, 'tool_execution_error'
  end

  # Só ids e a classe do erro: nada do que o modelo mandou, nada do cadastro.
  def registrar_falha(onde, erro)
    Rails.logger.warn("[autonomia][tool][consulta] #{onde} falhou slug=#{@tool.slug} conversa=#{@turno.conversation.id} " \
                      "agente=#{@agente&.id} #{erro.class}")
  end

  # O que o pré-disparo desta chamada deixou, ou um disparo agora. A execução TOMA o seu: a mesma chamada repetida depois
  # (outra rodada, "mais um igual") passa pelo reaproveitamento, com a ocorrência de agora.
  def tomar_disparo
    @chave = Chave.com_ocorrencia(@pedido, @turno.ocorrencia(@pedido))
    @turno.consultas.delete(@chamada || @chave) || disparar.tap { @turno.consultas.delete(identidade) }
  end

  def identidade
    @chamada || @chave
  end

  def janela
    @turno.janela_das_consultas(self.class.agora, ESPERA_DO_TURNO)
  end

  # Lê SÓ o estado, de `INTERVALO` em `INTERVALO`, até o prazo da janela; entre as leituras, a conexão do banco volta
  # ao pool. -> o último estado lido.
  def aguardar(run, janela)
    loop do
      status = ToolRun.where(id: run.id).pick(:status)
      restante = janela.last - self.class.agora
      return status if status != 'running' || restante <= 0

      ::Autonomia::Agents::Tools::ConexaoDoBanco.soltar
      self.class.pausar([INTERVALO, restante].min)
    end
  end

  # O resultado chegou. Quem marcou a entrega primeiro decide: este turno, ou um que já desistiu (o evento fala).
  # A resposta 2xx avança a ocorrência do turno: a próxima chamada idêntica é outro pedido (`Delivery#ocorrencia`).
  def entregar(run)
    run.reload
    return ja_com_o_evento(run) if !run.marcar_entregue! && run.entrega != ToolRun::ENTREGUE_NO_TURNO
    raise falha(run) unless run.resultado_ok?

    concluir(run)
    run.resultado_da_consulta
  end

  # Quem fala é o evento: rodando, o modelo avisa que está consultando; terminada, ele não repete o resultado.
  def ja_com_o_evento(run)
    return EM_ANDAMENTO unless FIM.include?(run.status)

    concluir(run) if run.resultado_ok?
    JA_INFORMADO
  end

  def concluir(run)
    @turno.concluir_execucao(@pedido, run.id) if @turno.respond_to?(:concluir_execucao)
  end

  # A falha gravada pelo job é a saída da `Recusa` (`{"error":"<categoria>: <status>", "resposta_do_sistema_externo":…}`):
  # volta a ser o erro do executor, para o `Bound` registrar a recusa e o modelo ler o mesmo texto do síncrono.
  def falha(run)
    dado = JSON.parse(run.resultado_da_consulta.to_s)
    Erro.new(dado['error'].to_s, trecho: dado['resposta_do_sistema_externo'])
  rescue JSON::ParserError
    Erro.new('tool_execution_error')
  end

  # A janela acabou. A desistência só vale sem resultado gravado; com ele, o turno entrega. A espera conta do começo
  # da janela da rodada.
  def desistir(run, janela)
    espera_ms = ((self.class.agora - janela.first) * 1000).round
    return entregar(run) unless run.marcar_desistencia!(espera_ms: espera_ms)

    Rails.logger.info("[autonomia][tool][consulta] turno_desistiu run=#{run.id} slug=#{run.slug} espera_ms=#{espera_ms}")
    EM_ANDAMENTO
  end

  # A execução com esta chave que ainda serve: a que roda, ou a concluída com 2xx (o turno refeito não chama de novo). A
  # que falhou não serve: chamar de novo, com a mesma chave, é o que o síncrono faz.
  def reaproveitada
    ToolRun.for_conversation(@turno.conversation.id).where(autonomia_agent_tool_id: @tool.id)
           .where('handle ->> ? = ?', ToolRun::CHAVE_DA_CONSULTA, @chave)
           .where("status = 'running' OR (status = 'done' AND handle @> ?)", { ToolRun::RESULTADO_OK => true }.to_json)
           .order(id: :desc).first
  end

  # Sob a trava da faixa, para duas passadas do mesmo pedido não abrirem duas. O job sai DEPOIS do commit.
  def abrir
    nova = false
    run = ToolRun.transaction do
      ToolRun.travar!(@turno.conversation.id, @tool.slug, faixa)
      existente = reaproveitada || pendurada
      next existente if existente

      nova = true
      aberta
    end
    enfileirar(run) if nova
    run
  end

  # O MESMO PEDIDO NUMA MENSAGEM NOVA: a execução viva da faixa que já chamou o sistema de fora é a deste turno também
  # (chamar de novo, com outra chave, gravaria o pedido duas vezes lá). A que ainda não chamou é trocada pela nova.
  def pendurada
    viva = ToolRun.for_conversation(@turno.conversation.id).find_by(status: 'running', slug: @tool.slug, faixa: faixa)
    return nil if viva.nil? || viva.superar_sem_chamada!

    viva.reload.running? ? viva : nil
  end

  def aberta
    run = ToolRun.open!(agent: @agente, slug: @tool.slug, arguments: @params, marcas: marcas, scope: escopo)
    raise ActiveRecord::RecordNotUnique, "consulta #{@tool.slug} não abriu" if run.nil?

    run.promote!(expected_chunks: 0, notify_customer: false,
                 expires_at: ::Autonomia::Agents::Tools::HttpAssincronaJob.vence_em(@tool.timeout_seconds))
    run
  end

  # Sem o job, a linha não pode ficar viva esperando quem nunca vem: fecha sem evento (o turno ainda não desistiu) e
  # sobe, para o turno recusar.
  def enfileirar(run)
    ::Autonomia::Agents::Tools::HttpAssincronaJob.perform_later(run.id)
  rescue StandardError
    run.finish!('failed', failure_code: 'consulta_nao_disparou')
    raise
  end

  def marcas
    { ToolRun::CHAVE_DA_CONSULTA => @chave, ToolRun::TEMPO_DA_CONSULTA => @tool.timeout_seconds,
      ToolRun::ABERTA_EM => Time.current.iso8601(3) }
  end

  def escopo
    { conversation_id: @turno.conversation.id, agent_inbox_id: @turno.agent_inbox&.id, faixa: faixa,
      origin_message_id: @turno.origin_message_id, autonomia_agent_tool_id: @tool.id }
  end

  # A faixa é o pedido (a ferramenta, os argumentos tipados e a ocorrência, sem o turno): outro pedido corre junto, e
  # duas chamadas idênticas da mesma rodada também; o mesmo, numa mensagem nova, cai na mesma faixa (`pendurada`).
  def faixa
    @faixa ||= "#{ToolRun::FAIXA_DA_CONSULTA}#{::Autonomia::Insurance::Faixa::SEPARADOR}" \
               "#{Chave.resumo([@tool.id, Chave.em_ordem(@params), @ocorrencia.to_i])[0, 16]}"
  end
end

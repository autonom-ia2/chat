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
# marca `entregue_no_turno` (com o turno que entregou, `ENTREGUE_POR`) ou `desistiu_do_turno`, e a desistência só vale
# sem resultado gravado. O job só dispara o evento com a desistência; sem marca nenhuma depois da janela, ele mesmo a
# marca (`HttpAssincronaJob.fechar`). Na corrida, a entrega acontece uma vez:
#   - o mesmo turno refeito relê o resultado;
#   - outro turno lê `JA_INFORMADO`, salvo quando o que entregou foi superado antes de postar (uma mensagem mais nova
#     do cliente, `turno_superado?`): aí este toma a entrega, para o resultado não se perder.
#
# REAPROVEITAR, NUNCA CHAMAR DUAS VEZES O MESMO PEDIDO:
#   - a mesma Idempotency-Key (o turno refeito, a mesma chamada de novo) reusa a execução que roda ou que concluiu com
#     2xx; a que falhou não é reusada: o turno chama de novo com a mesma chave, como no síncrono;
#   - o mesmo pedido numa mensagem nova (outra chave) se pendura na execução da conversa que já chamou o sistema de
#     fora; a que ainda não chamou é trocada pela nova (`superar_sem_chamada!`);
#   - a incerta (a chamada saiu e a resposta se perdeu) segura o mesmo pedido enquanto é recente (`Abertura`), e a
#     concluída que um turno superado entregou sem falar passa ao turno novo.
#
# Sem conversa (Testar, playground, Copiloto), sem a flag ou no turno de um evento, nada daqui roda: a ferramenta é
# síncrona, como no #2426.
class Autonomia::Agents::Tools::ConsultaNoTurno
  include ::Autonomia::Agents::Tools::ConsultaNoTurno::Abertura
  include ::Autonomia::Agents::Tools::ConsultaNoTurno::TurnoSuperado

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
  # A incerta já avisada numa mensagem à parte: o pedido saiu e a resposta se perdeu. Não há resultado a dar.
  INCERTA_JA_INFORMADA = 'Este mesmo pedido já foi enviado ao sistema, mas a resposta se perdeu, e o cliente já foi ' \
                         'avisado numa mensagem à parte de que não deu para confirmar e que a equipe vai conferir. Não ' \
                         'envie de novo, não diga que deu certo nem que deu errado; siga a conversa.'.freeze
  # O código da recusa quando a consulta nem chegou a sair (infraestrutura): o modelo lê `tool_execution_error`.
  NAO_DISPAROU = 'tool_execution_error: consulta_nao_disparou'.freeze
  FIM = %w[done failed].freeze
  # O agente de cotação (a Lia) fica fora: as ferramentas dela têm motor próprio.
  AGENTE_DE_COTACAO = 'insurance_quote'.freeze
  # A falha de infraestrutura que o turno engole com a recusa (e o log): o banco e o Redis. O resto é defeito nosso, e
  # vai também ao rastreador.
  ERROS_DE_INFRA = [ActiveRecord::ActiveRecordError, Redis::BaseError, RedisClient::Error].freeze
  # A leitura da espera: o resultado gravado, sem trazer o handle.
  COM_RESULTADO = Arel.sql("(handle->>'#{::Autonomia::Agents::ToolRun::RESULTADO_DA_CONSULTA}') IS NOT NULL")

  # O que o turno guarda de cada chamada disparada: a execução e a janela da rodada, ou a falha do disparo.
  Disparo = Struct.new(:run, :janela, :falhou, keyword_init: true)

  # Com conversa (o `Delivery` do turno, também o do principal quando quem chama é o ajudante) e a flag da conta. O turno
  # de um evento (`ResponderAoEvento`) roda síncrono: uma consulta aberta nele terminaria em outro evento, e o laço
  # evento -> consulta -> evento não teria fim.
  def self.aplica?(tool, turno)
    return false unless turno.respond_to?(:conversation) && turno.conversation.present?
    return false if turno.try(:turno_de_evento?)
    return false if do_agente_de_cotacao?(tool, turno)

    ligada?(tool.account)
  end

  def self.do_agente_de_cotacao?(tool, turno)
    [tool.try(:agent), turno.try(:agent_inbox)&.agent].compact.any? { |agente| agente.agent_type == AGENTE_DE_COTACAO }
  end

  def self.ligada?(account)
    account.feature_enabled?(FLAG)
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
  rescue *ERROS_DE_INFRA => e
    registrar_falha('disparo', e)
    @turno.consultas[identidade] = Disparo.new(falhou: true)
  rescue StandardError => e
    rastrear(e)
    registrar_falha('disparo', e)
    @turno.consultas[identidade] = Disparo.new(falhou: true)
  end

  # -> o texto que o modelo lê. Uma falha que chega na janela levanta `HttpExecutor::Error`, como o síncrono: o `Bound`
  # a registra e devolve a mesma recusa. O erro no meio da espera (o banco; o defeito nosso também vai ao rastreador)
  # não derruba o turno e não cala o resultado: com a execução aberta, o turno desiste e o evento fala (`EM_ANDAMENTO`);
  # `NAO_DISPAROU` só quando não há execução.
  def resultado
    @disparo = tomar_disparo
    raise Erro, NAO_DISPAROU if @disparo.falhou

    esperar(@disparo)
  rescue Erro
    raise
  rescue *ERROS_DE_INFRA => e
    falha_na_espera(e)
  rescue StandardError => e
    rastrear(e)
    falha_na_espera(e)
  end

  private

  def esperar(disparo)
    run = disparo.run.reload
    return ja_com_o_evento(run) if run.entrega == ToolRun::DESISTIU_DO_TURNO

    status, gravado = aguardar(run, disparo.janela)
    return EM_ANDAMENTO if status == 'superseded'
    return entregar(run) if FIM.include?(status) || gravado
    return desistir(run, disparo.janela) if status == 'running'

    raise Erro, 'tool_execution_error'
  end

  # O resultado não pode ficar mudo: com a execução aberta, este turno desiste (se ainda der) e o evento fala; se a
  # desistência também falhar, o job a marca quando a janela vencer (`HttpAssincronaJob.fechar`).
  def falha_na_espera(erro)
    registrar_falha('espera', erro)
    run = @disparo&.run
    raise Erro, NAO_DISPAROU if run.nil?

    desistir_sem_esperar(run)
    EM_ANDAMENTO
  end

  def desistir_sem_esperar(run)
    run.marcar_desistencia!(espera_ms: nil)
  rescue *ERROS_DE_INFRA => e
    registrar_falha('desistencia', e)
  end

  def rastrear(erro)
    ChatwootExceptionTracker.new(erro, account: @tool.account).capture_exception
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

  # Lê SÓ o estado e se há resultado, de `INTERVALO` em `INTERVALO`, até o prazo da janela; entre as leituras, a
  # conexão do banco volta ao pool. O resultado gravado com a linha viva é o job deixando a entrega para o turno
  # (`HttpAssincronaJob.fechar`). -> [o último estado lido, se o resultado está gravado].
  def aguardar(run, janela)
    loop do
      status, gravado = ToolRun.where(id: run.id).pick(:status, COM_RESULTADO)
      restante = janela.last - self.class.agora
      return [status, gravado] if status != 'running' || gravado || restante <= 0

      ::Autonomia::Agents::Tools::ConexaoDoBanco.soltar
      self.class.pausar([INTERVALO, restante].min)
    end
  end

  # O resultado chegou. Quem marcou a entrega primeiro decide (`entrega_deste_turno?`): este turno, ou outro (o evento,
  # ou um turno vivo, fala; a incerta já avisada tem texto próprio). A resposta 2xx avança a ocorrência do turno: a
  # próxima chamada idêntica é outro pedido (`Delivery#ocorrencia`).
  def entregar(run)
    run.reload
    return ja_com_o_evento(run) unless entrega_deste_turno?(run)

    entregue(run)
  end

  # A MARCA DE ENTREGA É DESTE TURNO: daqui em diante nenhuma falha vira `EM_ANDAMENTO` (ninguém mais falaria). O turno
  # devolve o resultado gravado, ou a falha gravada; o fechamento e a ocorrência que falham ficam no log e no rastreador.
  def entregue(run)
    encerrar(run)
    raise falha(run) unless run.resultado_ok?

    concluir(run)
    run.resultado_da_consulta
  end

  # Marca a entrega, ou relê quem marcou: o mesmo turno (refeito) entrega de novo; outro turno, só se o que entregou foi
  # superado antes de postar, e por compare-and-set (dois turnos novos não tomam os dois).
  def entrega_deste_turno?(run)
    return true if run.marcar_entregue!(por: @turno.turno)

    run.reload
    return false unless run.entrega == ToolRun::ENTREGUE_NO_TURNO
    return true if run.entregue_por == @turno.turno

    turno_superado?(run.entregue_por) && run.tomar_entrega!(anterior: run.entregue_por, por: @turno.turno)
  end

  # O turno que entregou fecha a linha que o job deixou viva para ele. A falha aqui não tira o resultado do turno: a
  # linha fica com a marca, e o job (quando a janela vence) ou o varredor a fecham.
  def encerrar(run)
    ::Autonomia::Agents::Tools::HttpAssincronaJob.fechar(run) if run.running?
  rescue StandardError => e
    sem_derrubar_a_entrega('fechamento', e)
  end

  # Quem fala é o evento (ou o turno que entregou): rodando, o modelo avisa que está consultando; com o resultado, ele
  # não repete. A incerta já foi avisada: não há resultado a não repetir, e o modelo não pode dizer que deu certo.
  def ja_com_o_evento(run)
    return EM_ANDAMENTO unless FIM.include?(run.status) || run.resultado_gravado?
    return INCERTA_JA_INFORMADA if run.incerta?

    concluir(run) if run.resultado_ok?
    JA_INFORMADO
  end

  def concluir(run)
    @turno.concluir_execucao(@pedido, run.id) if @turno.respond_to?(:concluir_execucao)
  rescue StandardError => e
    sem_derrubar_a_entrega('ocorrencia', e)
  end

  # Erro de infraestrutura só no log; o defeito nosso também no rastreador. Nos dois, o turno segue com o resultado.
  def sem_derrubar_a_entrega(onde, erro)
    rastrear(erro) unless ERROS_DE_INFRA.any? { |classe| erro.is_a?(classe) }
    registrar_falha(onde, erro)
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
end

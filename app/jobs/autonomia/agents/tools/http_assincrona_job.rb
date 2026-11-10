# A CHAMADA DA CONSULTA HTTP EM SEGUNDO PLANO (#1430, desenho D). Quem abre a execução e a enfileira é o turno
# (`Tools::ConsultaNoTurno`), que espera por ela até a janela da rodada.
#
# UMA chamada, sem poll, na fila própria (`AgentToolsQueue`): uma conta com o sistema lento não ocupa as filas das
# outras. Sem retry do Sidekiq: uma nova tentativa automática chamaria o sistema de fora de novo. A ordem que protege a
# chamada única, a mesma do `SUBMITTED_KEY` da Lia:
#   1. com o resultado já gravado, só fecha;
#   2. com a chamada já feita e sem resultado, NÃO chama: se foi este mesmo job (o Sidekiq o devolveu à fila no
#      desligamento, mesmo com `retry: false`), o worker morreu no meio da chamada, e a consulta fecha como incerta na
#      hora; se foi outra passada, ela pode estar chamando, e quem decide é o varredor;
#   3. cede a vez quando a conta ocupa mais da metade do capsule e outra conta espera (`ceder_a_vez?`);
#   4. reivindica a linha: renova o prazo com o tempo gravado na abertura e anota a espera na fila;
#   5. confere a ferramenta e a autorização;
#   6. marca `chamada_feita` por compare-and-set — só em linha viva, sem chamada e sem resultado. Quem não marca não
#      chama: a superada antes de começar para aqui;
#   7. solta a conexão do banco, chama com a chave e o tempo da abertura;
#   8. grava o resultado uma vez (a resposta com os segredos do cadastro mascarados e o teto do síncrono), com conexão
#      nova;
#   9. fecha: o evento só sai se o turno desistiu (`ENTREGA`), e sai ANTES do `finish!`, porque o slot dele só é
#      adquirido em linha viva. Sem marca de entrega e com a janela do turno ainda aberta, a linha fica viva com o
#      resultado: o turno que espera o lê, marca a entrega e fecha. Passada a janela sem marca (o turno morreu), a
#      desistência é marcada aqui por compare-and-set e o evento fala: o resultado nunca fica mudo.
#
# A ferramenta é resolvida pelo id gravado na linha, nunca pelo slug.
#
# DEPLOY NO MEIO: o desligamento devolve o job interrompido à fila (passo 2); o SIGKILL o perde, e quem recupera é o
# `ReapStaleRunsJob` (`fechar_consulta`), pelo que a linha mostra.
class Autonomia::Agents::Tools::HttpAssincronaJob < ApplicationJob
  FILA = AgentToolsQueue::FILA.to_sym
  queue_as FILA
  sidekiq_options retry: false

  ToolRun = ::Autonomia::Agents::ToolRun
  Evento = ::Autonomia::Agents::Tools::Evento
  Recusa = ::Autonomia::Agents::Tools::Recusa
  Aviso = ::Autonomia::Agents::Operate::AvisoAoAtendente
  # O prazo da linha passa do tempo da ferramenta por esta folga: a espera na fila e a abertura da conexão. O varredor
  # ainda soma a dele (`ReapStaleRunsJob::GRACE`) antes de agir. Folga de desenho, não medida.
  FOLGA = 2.minutes
  # Quanto o job que cedeu a vez espera para tentar de novo. Poucos segundos: a outra conta só precisa pegar a thread.
  ESPERA_DA_VEZ = 3.seconds
  # Além da janela do turno: a última leitura dele e a marca da desistência. Folga de desenho, não medida.
  FOLGA_DA_JANELA = 2.seconds
  # O defeito nosso antes de o pedido sair: a mesma categoria do síncrono para falha de execução.
  DEFEITO_ANTES_DO_ENVIO = 'tool_execution_error'.freeze

  def self.vence_em(segundos)
    segundos.to_i.seconds.from_now + FOLGA
  end

  def self.tempo(run)
    run.handle.to_h.fetch(ToolRun::TEMPO_DA_CONSULTA)
  end

  # A segunda chance do varredor, para o job que começou e morreu ANTES de chamar: -> true quando enfileirou.
  def self.reenfileirar(run, vencida_antes_de:)
    return false unless run.reenfileirar_consulta!(expires_at: vence_em(tempo(run)), vencida_antes_de: vencida_antes_de)

    perform_later(run.id)
    true
  end

  # O job que nunca começou: de volta à fila, sem gastar a segunda chance (não houve chamada).
  def self.reenfileirar_sem_comecar(run, vencida_antes_de:)
    return false unless run.reenfileirar_sem_comecar!(expires_at: vence_em(tempo(run)), vencida_antes_de: vencida_antes_de)

    perform_later(run.id)
    true
  end

  # O job que começou duas vezes e morreu antes de chamar: falha, e o agente diz que não conseguiu. O turno já foi
  # embora há muito: sem marca de entrega, quem fala é o evento (a desistência é marcada no `fechar`, depois do
  # fechamento que confere o prazo).
  def self.abandonar(run, vencida_antes_de:)
    return false unless run.abandonar_consulta!(Recusa.saida('execucao_abandonada'), vencida_antes_de: vencida_antes_de)

    fechar(run.reload)
  end

  # A chamada saiu e a resposta se perdeu: não chama de novo. Quem atende confere se o pedido foi registrado lá; o
  # cliente ouve que não deu para confirmar (`Evento`, pelo código `INCERTA`). `vencida_antes_de`: o varredor. A
  # desistência é marcada no `fechar`, depois do fechamento (o turno que ainda espera lê a incerteza).
  def self.incerta(run, vencida_antes_de: nil)
    return leitura_perdida(run, vencida_antes_de: vencida_antes_de) if run.ferramenta&.pronta?
    return false unless run.fechar_incerta!(Recusa.saida(ToolRun::INCERTA), vencida_antes_de: vencida_antes_de)

    Aviso.consulta_incerta(run)
    fechar(run.reload)
  end

  # #2858: a ferramenta pronta só LÊ dado público; a resposta perdida não deixa nada registrado do lado de lá. Sem aviso
  # a quem atende e sem a incerteza: o modelo lê "não consegui consultar agora", como em qualquer falha da fonte.
  def self.leitura_perdida(run, vencida_antes_de:)
    texto = ::Autonomia::FerramentasProntas::Resposta.nao_consegui
    return false unless run.fechar_leitura_perdida!(texto, vencida_antes_de: vencida_antes_de)

    fechar(run.reload)
  end

  # Com o resultado gravado. Sem marca de entrega e na janela do turno: fica viva para o turno, e esta passada volta
  # quando a janela vence. Fora dela, sem marca: a desistência por compare-and-set (o turno que marcou antes ganha). O
  # evento só com a desistência, e antes do `finish!`. -> false quando deixou a linha para o turno.
  def self.fechar(run)
    return esperar_o_turno(run) if run.entrega.nil? && !janela_vencida?(run)

    falar_se_ninguem_entrega(run)
    ok = run.resultado_ok?
    run.finish!(ok ? 'done' : 'failed', failure_code: ok ? nil : run.handle.to_h[ToolRun::CODIGO_DA_CONSULTA])
  end

  def self.falar_se_ninguem_entrega(run)
    run.reload unless run.entrega || run.desistir_sem_turno!
    return unless run.entrega == ToolRun::DESISTIU_DO_TURNO

    Evento.disparar(run, run.resultado_ok? ? Evento::CONSULTA_CONCLUIDA : Evento::CONSULTA_FALHOU)
  end

  # A janela do turno conta do pré-disparo da rodada, que vem antes da abertura: vence no máximo `ESPERA_DO_TURNO`
  # depois de `ABERTA_EM`, mais a folga da última leitura do turno. Sem a marca, vencida.
  def self.fim_da_janela(run)
    aberta_em = Time.zone.parse(run.handle.to_h[ToolRun::ABERTA_EM].to_s)
    aberta_em && (aberta_em + ::Autonomia::Agents::Tools::ConsultaNoTurno::ESPERA_DO_TURNO.seconds + FOLGA_DA_JANELA)
  end

  def self.janela_vencida?(run)
    fim = fim_da_janela(run)
    fim.nil? || Time.current >= fim
  end

  # Volta quando a janela vence: se nenhum turno marcou a entrega até lá, esta passada fecha com o evento. Sem a fila
  # (Redis fora), sobe: a linha fica viva com o resultado, e o varredor fecha (`ReapStaleRunsJob#fechar_consulta`).
  def self.esperar_o_turno(run)
    set(wait_until: fim_da_janela(run)).perform_later(run.id)
    false
  end

  def perform(run_id)
    inicio = agora
    run = consulta_viva(run_id)
    return if run.nil? || sem_chamar?(run)

    tool = ferramenta(run)
    return indisponivel(run) if tool.nil?
    return if bloqueada?(run)

    chamar_uma_vez(run, tool, inicio)
  end

  private

  def agora
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def consulta_viva(run_id)
    run = ToolRun.find_by(id: run_id)
    run if run&.running? && run.consulta_http?
  end

  # As paradas antes da chamada, na ordem do cabeçalho (passos 1 a 4). -> true quando esta passada não chama.
  def sem_chamar?(run)
    return ceder_a_vez?(run) || !reivindicar(run) unless run.resultado_gravado? || run.chamada_feita?

    run.resultado_gravado? ? self.class.fechar(run) : reentrada(run)
    true
  end

  # A chamada já saiu nesta linha e não há resultado. Este mesmo job de volta: o worker morreu no meio da chamada.
  # Outra passada: ela pode estar chamando agora.
  def reentrada(run)
    return log(run, 'chamada_em_voo_de_outra_passada') unless run.handle.to_h[ToolRun::PASSADA] == job_id

    log(run, 'reentrada_depois_da_chamada') if self.class.incerta(run)
  end

  # A EQUIDADE ENTRE CONTAS NO CAPSULE (o isolamento entre filas é o `AgentToolsQueue`; este é o outro). A conta deste
  # job já ocupa mais da metade das threads E uma consulta de outra conta espera: o job volta à fila em poucos
  # segundos, sem chamar e sem prender a thread. Fila livre, a conta usa todas. Nada é recusado. A ocupação sai da
  # própria tabela (as linhas vivas que começaram e não têm resposta), no índice das ativas: uma leitura, sem varrer a
  # fila no Redis, cujo payload só tem o id da linha.
  def ceder_a_vez?(run)
    return false unless ToolRun.consultas_em_voo(run.account_id) * 2 > AgentToolsQueue.concorrencia
    return false unless ToolRun.consulta_esperando_de_outra_conta?(run.account_id)
    return false unless run.adiar_comeco!(expires_at: self.class.vence_em(self.class.tempo(run)))

    self.class.set(wait: ESPERA_DA_VEZ).perform_later(run.id)
    log(run, 'cedeu_a_vez')
    true
  end

  def reivindicar(run)
    aberta_em = Time.zone.parse(run.handle.to_h[ToolRun::ABERTA_EM].to_s)
    fila_ms = aberta_em && ((Time.current - aberta_em) * 1000).round
    run.reivindicar!(expires_at: self.class.vence_em(self.class.tempo(run)), fila_ms: fila_ms)
  end

  def chamar_uma_vez(run, tool, inicio)
    chave = run.handle.to_h.fetch(ToolRun::CHAVE_DA_CONSULTA)
    return log(run, 'chamada_ja_feita') unless run.marcar_chamada!(passada: job_id)

    # Lido antes de soltar a conexão: depois dela, só a escrita do resultado volta ao banco.
    agente = run.agent
    banco_antes_ms = ms_desde(inicio)
    ::Autonomia::Agents::Tools::ConexaoDoBanco.soltar
    saida, codigo, api_ms = chamar(run, tool, agente, chave)
    depois = agora
    run.gravar_resultado!(saida, sucesso: codigo.nil?, codigo: codigo || @desfecho_da_pronta, api_ms: api_ms)
    run.reload
    run.running? ? self.class.fechar(run) : fora_do_turno(run, saida, codigo, tool)
    log(run, "fim fila_ms=#{run.handle[ToolRun::FILA_MS]} api_ms=#{api_ms} banco_antes_ms=#{banco_antes_ms} " \
             "banco_depois_ms=#{ms_desde(depois)}")
    raise @defeito if @defeito
  end

  # -> [o texto do desfecho, o código da falha ou nil, o tempo da API]. Só os erros esperados da chamada viram desfecho
  # (o executor já traduz rede, tempo, HTTP e modelo para `HttpExecutor::Error`); o defeito nosso vai ao rastreador.
  # Antes de o pedido sair (`HttpExecutor#enviada?`), o defeito é falha certa: nada chegou lá, e a consulta falha como
  # as outras (o defeito sobe depois do fechamento). Depois de sair, sobe na hora: a linha fica com a chamada feita e
  # sem resultado, e fecha como incerta.
  def chamar(run, tool, agente, chave)
    bound = ::Autonomia::Agents::Tools::Bound.new(agent: agente, record: tool)
    comeco = agora
    chamada = executor(run, tool, chave)
    texto = chamada.call
    # #2858: a pronta responde sempre ao modelo (até o "não consegui consultar agora", que é o texto que ele precisa
    # ler); o desfecho de falha dela vai só para o registro da linha (`CODIGO_DA_CONSULTA`).
    @desfecho_da_pronta = chamada.try(:codigo)
    [bound.cabendo(texto), nil, ms_desde(comeco)]
  rescue ::Autonomia::Agents::Tools::HttpExecutor::Error => e
    [bound.texto_da_recusa_http(e), bound.categoria_da_recusa_http(e), ms_desde(comeco)]
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: run.account).capture_exception
    raise if chamada&.enviada?

    @defeito = e
    [Recusa.saida(DEFEITO_ANTES_DO_ENVIO), DEFEITO_ANTES_DO_ENVIO, ms_desde(comeco)]
  end

  # #2858: a ferramenta pronta executa pela fonte do catálogo (`FerramentasProntas::Execucao`), com o prazo dela.
  def executor(run, tool, chave)
    ::Autonomia::FerramentasProntas.executor_para(tool, params: run.arguments, chave: chave, higienizar: true,
                                                        segundos: self.class.tempo(run))
  end

  # A linha deixou de ser desta passada enquanto ela chamava: trocada por um pedido mais novo, ou fechada pelo varredor.
  # O resultado não é falado; se o sistema de fora fez o pedido (2xx), quem atende fica sabendo, com a resposta.
  # #2858: a pronta só leu dado público; não há pedido do lado de lá para quem atende conferir.
  def fora_do_turno(run, saida, codigo, tool)
    return unless codigo.nil?
    return if tool.pronta?
    return unless run.status == 'superseded' || ToolRun::FECHADAS_SEM_RESPOSTA.include?(run.handle.to_h[ToolRun::CODIGO_DA_CONSULTA])

    Aviso.consulta_antiga(run, run.status == 'superseded' ? 'consulta_antiga' : 'consulta_fechada_concluiu', resultado: saida)
  end

  # Desligada ou apagada depois da abertura. Da mesma conta, pelo id; a ferramenta pode ser de um ajudante.
  def ferramenta(run)
    ::Autonomia::Agents::Tool.enabled.find_by(id: run.autonomia_agent_tool_id, account_id: run.account_id)
  end

  def indisponivel(run)
    run.gravar_resultado!(Recusa.saida('ferramenta_indisponivel'), sucesso: false, codigo: 'ferramenta_indisponivel', api_ms: nil)
    self.class.fechar(run.reload)
  end

  # O operador puxou o freio depois da abertura (conta, agente, allowlist), ou a conversa mudou de dono: para sem chamar,
  # como o `AsyncRunJob`. O resultado `bloqueada` é gravado, e fecha como as outras falhas (`fechar`, `failed` com o
  # código `bloqueada`; `blocked` mataria o evento, `EventoJob` não fala de execução morta): o turno
  # que ainda espera o lê como recusa, e sem turno o evento `consulta_falhou` fala (o cliente não fica sem resposta; sem
  # quem possa falar, vira nota). O motivo (`nao_autorizado`, `vinculo_mudou`) vai ao log.
  def bloqueada?(run)
    codigo = motivo_do_bloqueio(run)
    return false if codigo.nil?

    log(run, "bloqueada motivo=#{codigo}")
    run.gravar_resultado!(Recusa.saida(ToolRun::BLOQUEADA), sucesso: false, codigo: ToolRun::BLOQUEADA, api_ms: nil)
    self.class.fechar(run.reload)
    true
  end

  def motivo_do_bloqueio(run)
    vinculo = ::Autonomia::Agents::Operate.authorized_agent_inbox(run.conversation)
    if vinculo.blank? then 'nao_autorizado'
    elsif run.agent_inbox_id.present? && vinculo.id != run.agent_inbox_id then 'vinculo_mudou'
    end
  end

  def ms_desde(comeco)
    ((agora - comeco) * 1000).round
  end

  def log(run, texto)
    Rails.logger.info("[autonomia][tool][http_assincrona] run=#{run.id} #{texto}")
  end
end

# O "esperar" e o "esperar até" no executor (#2414 F3, G11, lote 4 #2682). Fica fora do Executor para ele seguir sendo a
# lista dos passos; usa os métodos dele (aguardar, registrar, condicao?, valores, alvo) e o estado da rodada (@retomando,
# @execucao, @roteiro).
#
# Sem prazo (#2750): a espera só termina pela condição, e não tem caminho "se vencer" (a Receita recusa). O `due_at`
# dela não é prazo: é a próxima conferência, daqui a CONFERENCIA. A varredura a acorda pelo caminho de sempre, a rodada
# confere o que confere ao retomar (o motor, a automação ligada, o alvo, quem ligou: Executor#impedimento) e a condição;
# nada mudou, volta a esperar, sem registro novo. Assim a espera sem prazo nunca fica aberta para sempre depois que a
# automação parou ou quem ligou perdeu o acesso (fecha com registro e motivo), o aviso perdido (fila fora do ar) é
# recuperado em até um dia, e a varredura, a reserva da Escuta e o índice seguem contando com o `due_at` preenchido.
module Autonomia::Automacao::EsperaNoExecutor
  Duracao = ::Autonomia::Automacao::Duracao
  CONFERENCIA = 1.day

  private

  def esperar(passo)
    return @roteiro.seguinte(passo['id']) if @retomando

    aguardar(passo, Time.current + Duracao.de(passo['duracao']))
  end

  def esperar_ate(passo)
    espera = janela_da_espera(passo)
    return cumprida(passo) if condicao?(passo['condicao'], valores(espera: espera))
    return aguardar_sem_prazo(passo, espera) if Duracao.sem_prazo?(passo['prazo'])
    return aguardar_condicao(passo, espera, espera.begin + Duracao.de(passo['prazo'])) unless @retomando
    return aguardar_condicao(passo, espera, @execucao.due_at, registrar: false) if @execucao.due_at&.future?

    registrar(passo['id'], 'pulado', 'prazo_vencido')
    @roteiro.entrar(passo, 'se_vencer')
  end

  # A corrida do acordar (lote 4, #2682): a condição foi lida com o alvo desta rodada, e só depois a execução passa a
  # `esperando`. O card, a conversa ou o gatilho que mudam nessa janela acham a execução ainda andando, e ninguém a
  # acorda. Por isso, já gravada a espera, confere uma vez de novo com o alvo relido; cumprida, reserva pela mesma
  # reserva da Escuta (o Despertador), e a rodada nova segue pelo caminho normal. A reserva só troca `esperando` por
  # `andando` uma vez: o aviso que chegar junto não roda a execução duas vezes. O erro ao gravar a espera sobe, como em
  # qualquer passo (a rodada registra a quebra).
  def aguardar_condicao(passo, espera, ate, registrar: true, dados: nil)
    aguardar(passo, ate, registrar: registrar, dados: dados)
    reconferir_a_espera(passo, espera)
    nil
  end

  # Só depois da espera gravada: erro aqui vai para o log, e o prazo segue pelo relógio.
  def reconferir_a_espera(passo, espera)
    esperando = ::Autonomia::Automacao::Execucao.find_by(id: @execucao.id, estado: 'esperando')
    @alvo = @contexto = nil
    ::Autonomia::Automacao::Despertador.acordar(esperando) if esperando && alvo && condicao?(passo['condicao'], valores(espera: espera))
  rescue StandardError => e
    ::Autonomia::Automacao::Escuta.registrar_erro("não reconferiu ao esperar execucao=#{@execucao.id}", e)
  end

  # Registra só ao entrar: o começo da espera fica no registro (`desde`), porque o `due_at` muda a cada conferência.
  def aguardar_sem_prazo(passo, espera)
    aguardar_condicao(passo, espera, Time.current + CONFERENCIA, registrar: !@retomando,
                                                                 dados: { 'sem_prazo' => true, 'desde' => espera.begin.iso8601(6) })
  end

  # A janela do "esperar até", para a resposta que chegou durante ele (G11): na primeira conferência, de agora em diante;
  # ao retomar, do começo (o prazo gravado menos a duração dele, na versão em que a execução entrou) até o prazo. A
  # execução foi lida antes da troca, com o `due_at` da espera. Resposta depois do prazo não conta: o prazo venceu. Sem
  # prazo, do começo gravado no registro em diante.
  def janela_da_espera(passo)
    return Duracao.janela(passo['prazo'], (@execucao.due_at if @retomando)) unless Duracao.sem_prazo?(passo['prazo'])

    (@retomando ? inicio_da_espera(passo) : Time.current)..
  end

  # O registro da execução aberta não sai pela limpeza (LimparRegistrosJob): o começo fica enquanto ela espera.
  def inicio_da_espera(passo)
    entrada = ::Autonomia::Automacao::Registro.where(execucao_id: @execucao.id, passo: passo['id'], resultado: 'ok').order(:id).first
    desde = entrada&.dados&.dig('desde')
    desde ? Time.zone.parse(desde) : @execucao.created_at
  end

  def cumprida(passo) = registrar(passo['id'], 'ok').then { @roteiro.seguinte(passo['id']) }
end

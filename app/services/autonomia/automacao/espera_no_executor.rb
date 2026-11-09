# O "esperar" e o "esperar até" no executor (#2414 F3, G11, lote 4 #2682). Fica fora do Executor para ele seguir sendo a
# lista dos passos; usa os métodos dele (aguardar, registrar, condicao?, valores, alvo) e o estado da rodada (@retomando,
# @anterior, @execucao, @roteiro).
#
# Sem prazo (#2750): a espera só termina pela condição, e não tem caminho "se vencer" (a Receita recusa). O `due_at`
# dela não é prazo: é a próxima conferência, daqui a CONFERENCIA. A varredura a acorda pelo caminho de sempre, a rodada
# confere o que confere ao retomar (o motor, a automação ligada, o alvo, quem ligou: Executor#impedimento) e a condição;
# nada mudou, volta a esperar, sem registro novo. Assim a espera sem prazo nunca fica aberta para sempre depois que a
# automação parou ou quem ligou perdeu o acesso (fecha com registro e motivo), o aviso perdido (fila fora do ar) é
# recuperado em até um dia, e a varredura, a reserva da Escuta e o índice seguem contando com o `due_at` preenchido.
#
# Enquanto espera (G63, G64; regras em EnquantoEspera), cada rodada no "esperar até", nesta ordem:
# 1. confere a condição. Com `conferir_as`, só na conferência marcada (o `due_at` chegou) ou na volta do galho; acordada
#    por mensagem ou pelo card antes da hora, não confere;
# 2. com `a_cada_mensagem`, a mensagem do cliente depois do marco (a régua do G31, Resposta.novas_desde) entra no galho,
#    com o registro `mensagem_do_cliente` e a vez;
# 3. senão, volta a esperar: com `conferir_as`, até a próxima hora marcada no fuso da conta (Tempo.proxima_hora).
# O marco fica no registro do próprio "esperar até": gravado na entrada e de novo a cada volta do galho, que registra
# `voltou_a_esperar` com o marco lido no fim do último passo dele. A mensagem que chegou enquanto o galho rodava não
# abre outra rodada (decisão 11); a que chega depois do fim do galho, sim.
module Autonomia::Automacao::EsperaNoExecutor
  Duracao = ::Autonomia::Automacao::Duracao
  EnquantoEspera = ::Autonomia::Automacao::EnquantoEspera
  CONFERENCIA = 1.day

  private

  def esperar(passo)
    return @roteiro.seguinte(passo['id']) if @retomando

    aguardar(passo, Time.current + Duracao.de(passo['duracao']))
  end

  def esperar_ate(passo)
    voltou = voltou_do_galho?(passo)
    @marco_da_volta = marco_novo(passo) if voltou
    espera = janela_da_espera(passo, voltou)
    return cumprida(passo) if conferir_agora?(passo, voltou) && condicao?(passo['condicao'], valores(espera: espera))
    return entrar_no_galho(passo) if mensagem_para_o_galho?(passo)
    return aguardar_sem_prazo(passo, espera, voltou) if Duracao.sem_prazo?(passo['prazo'])

    esperar_o_prazo(passo, espera, voltou)
  end

  # Com prazo: espera até ele (a entrada sempre espera); vencido, segue pelo "se vencer".
  def esperar_o_prazo(passo, espera, voltou)
    ate = prazo_da_espera(passo, espera, voltou)
    return aguardar_com_prazo(passo, espera, ate, voltou) if ate&.future? || !(@retomando || voltou)

    registrar(passo['id'], 'pulado', 'prazo_vencido')
    @roteiro.entrar(passo, 'se_vencer')
  end

  # Na entrada, do começo da espera; ao retomar, o `due_at` (a execução foi lida antes da troca); na volta do galho, o
  # prazo gravado na entrada: o galho não recomeça o prazo.
  def prazo_da_espera(passo, espera, voltou)
    return @execucao.due_at if @retomando
    return prazo_gravado(passo) if voltou

    espera.begin + Duracao.de(passo['prazo'])
  end

  def aguardar_com_prazo(passo, espera, ate, voltou)
    return aguardar_condicao(passo, espera, ate, registrar: false) if @retomando
    return voltar_a_esperar(passo, espera, ate, 'ate' => ate.iso8601) if voltou

    aguardar_condicao(passo, espera, ate, dados: { 'ate' => ate.iso8601, **marco_novo(passo) })
  end

  # Registra só ao entrar e na volta do galho: o começo da espera fica no registro (`desde`), porque o `due_at` muda a
  # cada conferência.
  def aguardar_sem_prazo(passo, espera, voltou)
    ate = proxima_conferencia(passo)
    return aguardar_condicao(passo, espera, ate, registrar: false) if @retomando

    dados = { 'sem_prazo' => true, **passo.slice('conferir_as') }
    return voltar_a_esperar(passo, espera, ate, dados) if voltou

    aguardar_condicao(passo, espera, ate, dados: dados.merge('desde' => espera.begin.iso8601(6), **marco_novo(passo)))
  end

  # A próxima conferência sem prazo: daqui a CONFERENCIA; com `conferir_as`, a hora marcada que vem (a de agora, se a
  # rodada acordou antes dela).
  def proxima_conferencia(passo)
    return Time.current + CONFERENCIA unless EnquantoEspera.conferir_as?(passo)
    return @execucao.due_at if @retomando && @execucao.due_at&.future?

    ::Autonomia::Automacao::Tempo.proxima_hora(@account, passo['conferir_as'])
  end

  # A corrida do acordar (lote 4, #2682): a condição foi lida com o alvo desta rodada, e só depois a execução passa a
  # `esperando`. O card, a conversa ou o gatilho que mudam nessa janela acham a execução ainda andando, e ninguém a
  # acorda. Por isso, já gravada a espera, confere uma vez de novo com o alvo relido; cumprida, reserva pela mesma
  # reserva da Escuta (o Despertador), e a rodada nova segue pelo caminho normal. A reserva só troca `esperando` por
  # `andando` uma vez: o aviso que chegar junto não roda a execução duas vezes. O erro ao gravar a espera sobe, como em
  # qualquer passo (a rodada registra a quebra).
  def aguardar_condicao(passo, espera, ate, registrar: true, dados: nil)
    aguardar(passo, ate, registrar: registrar, dados: dados)
    reconferir_a_espera(passo, espera, ate)
    nil
  end

  # Só depois da espera gravada: erro aqui vai para o log, e o prazo segue pelo relógio.
  def reconferir_a_espera(passo, espera, ate)
    esperando = ::Autonomia::Automacao::Execucao.find_by(id: @execucao.id, estado: 'esperando')
    @alvo = @contexto = nil
    ::Autonomia::Automacao::Despertador.acordar(esperando) if esperando && alvo && acordar_de_novo?(passo, espera, ate)
  rescue StandardError => e
    ::Autonomia::Automacao::Escuta.registrar_erro("não reconferiu ao esperar execucao=#{@execucao.id}", e)
  end

  # A condição (a espera com hora marcada não confere fora dela) ou, com o galho, a mensagem do cliente que chegou
  # enquanto a espera era gravada. Passado o teto, a mensagem não acorda: acordaria de novo a cada rodada.
  def acordar_de_novo?(passo, espera, ate)
    return true if !EnquantoEspera.conferir_as?(passo) && condicao?(passo['condicao'], valores(espera: espera))

    EnquantoEspera.a_cada?(passo) && voltas_do_galho(passo) < EnquantoEspera::A_CADA_TETO &&
      cliente_escreveu?(passo, (ate unless Duracao.sem_prazo?(passo['prazo'])))
  end

  # Com `conferir_as`, só na conferência marcada (o `due_at` da espera, lido antes da troca, já chegou) ou na volta do
  # galho; sem ele, sempre.
  def conferir_agora?(passo, voltou)
    return true if voltou || !EnquantoEspera.conferir_as?(passo)

    @retomando && @execucao.due_at.present? && @execucao.due_at <= Time.current
  end

  # Só ao retomar: na entrada o marco é agora, e na volta do galho a mensagem que chegou durante ele já foi atendida.
  def mensagem_para_o_galho?(passo)
    return false unless @retomando && EnquantoEspera.a_cada?(passo)
    return false unless cliente_escreveu?(passo, (@execucao.due_at unless Duracao.sem_prazo?(passo['prazo'])))
    return true if voltas_do_galho(passo) < EnquantoEspera::A_CADA_TETO

    registrar(passo['id'], 'pulado', 'teto_a_cada') unless registros_da_espera(passo).exists?(motivo: 'teto_a_cada')
    false
  end

  def entrar_no_galho(passo)
    registrar(passo['id'], 'ok', 'mensagem_do_cliente', { 'vez' => voltas_do_galho(passo) + 1, **marco_novo(passo) })
    @roteiro.entrar(passo, EnquantoEspera::A_CADA)
  end

  # A volta do galho: o marco é o do fim do último passo dele, lido em esperar_ate antes de conferir a condição. A
  # mensagem que chega depois do galho e antes da espera gravada fica depois do marco: a reconferência a vê e ela abre a
  # próxima volta, em vez de ser absorvida. A espera segue com o mesmo prazo (ou a próxima conferência).
  def voltar_a_esperar(passo, espera, ate, dados)
    registrar(passo['id'], 'ok', 'voltou_a_esperar', dados.merge({ 'volta' => voltas_do_galho(passo), **@marco_da_volta }))
    aguardar_condicao(passo, espera, ate, registrar: false)
  end

  # O passo de antes nesta rodada (Executor#dar) estava dentro do galho deste "esperar até": o galho acabou.
  def voltou_do_galho?(passo) = @anterior.present? && @roteiro.no_galho?(@anterior, passo['id'])

  # `ate`: com prazo, a mensagem depois dele não conta (o prazo venceu); sem prazo, nil.
  def cliente_escreveu?(passo, ate)
    marco = registros_da_espera(passo).where("dados ->> 'marco' IS NOT NULL").order(:id).last&.dados&.fetch('marco')
    marco.present? && ::Autonomia::Automacao::Resposta.cliente_depois?(contexto.contato, marco, ate, @definicao.ligada_por)
  end

  def marco_novo(passo)
    return {} unless EnquantoEspera.a_cada?(passo)

    { 'marco' => ::Autonomia::Automacao::Resposta.marco(contexto.contato, @definicao.ligada_por) }
  end

  def voltas_do_galho(passo) = registros_da_espera(passo).where(motivo: 'mensagem_do_cliente').count

  def registros_da_espera(passo) = ::Autonomia::Automacao::Registro.where(execucao_id: @execucao.id, passo: passo['id'])

  def prazo_gravado(passo)
    gravado = registros_da_espera(passo).where("dados ->> 'ate' IS NOT NULL").order(:id).last&.dados&.fetch('ate')
    gravado ? Time.zone.parse(gravado) : Time.current
  end

  # A janela do "esperar até", para a resposta que chegou durante ele (G11): na primeira conferência, de agora em diante;
  # ao retomar, do começo (o prazo gravado menos a duração dele, na versão em que a execução entrou) até o prazo. A
  # execução foi lida antes da troca, com o `due_at` da espera. Resposta depois do prazo não conta: o prazo venceu. Sem
  # prazo, do começo gravado no registro em diante. Na volta do galho, como ao retomar.
  #
  # A volta ao mesmo "esperar até" na mesma rodada (o laço dos documentos, G46) começa no instante em que ele foi
  # cumprido, não agora: a 2ª e a 3ª foto que chegaram enquanto a IA lia a 1ª (a execução andando, sem ninguém para
  # acordar) contam, e o laço roda de novo para elas.
  def janela_da_espera(passo, voltou)
    return janela_sem_prazo(passo, voltou) if Duracao.sem_prazo?(passo['prazo'])
    return Duracao.janela(passo['prazo'], @execucao.due_at) if @retomando
    return Duracao.janela(passo['prazo'], prazo_gravado(passo)) if voltou

    @cumprida_em&.key?(passo['id']) ? (@cumprida_em[passo['id']]..) : Duracao.janela(passo['prazo'], nil)
  end

  def janela_sem_prazo(passo, voltou)
    return (@cumprida_em[passo['id']]..) if @cumprida_em&.key?(passo['id'])

    (@retomando || voltou ? inicio_da_espera(passo) : Time.current)..
  end

  # O registro da execução aberta não sai pela limpeza (LimparRegistrosJob): o começo fica enquanto ela espera. O da
  # última entrada: o laço dos documentos (G46) volta ao mesmo "esperar até" e grava um começo novo.
  def inicio_da_espera(passo)
    entrada = registros_da_espera(passo).where(resultado: 'ok').where("dados ->> 'desde' IS NOT NULL").order(:id).last
    desde = entrada&.dados&.dig('desde')
    desde ? Time.zone.parse(desde) : @execucao.created_at
  end

  def cumprida(passo)
    (@cumprida_em ||= {})[passo['id']] = Time.current
    registrar(passo['id'], 'ok').then { @roteiro.seguinte(passo['id']) }
  end
end

# O "esperar" e o "esperar até" no executor (#2414 F3, G11, lote 4 #2682). Fica fora do Executor para ele seguir sendo a
# lista dos passos; usa os métodos dele (aguardar, registrar, condicao?, valores, alvo) e o estado da rodada (@retomando,
# @execucao, @roteiro).
module Autonomia::Automacao::EsperaNoExecutor
  Duracao = ::Autonomia::Automacao::Duracao

  private

  def esperar(passo)
    return @roteiro.seguinte(passo['id']) if @retomando

    aguardar(passo, Time.current + Duracao.de(passo['duracao']))
  end

  def esperar_ate(passo)
    espera = janela_da_espera(passo)
    return cumprida(passo) if condicao?(passo['condicao'], valores(espera: espera))
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
  def aguardar_condicao(passo, espera, ate, registrar: true)
    aguardar(passo, ate, registrar: registrar)
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

  # A janela do "esperar até", para a resposta que chegou durante ele (G11): na primeira conferência, de agora em diante;
  # ao retomar, do começo (o prazo gravado menos a duração dele, na versão em que a execução entrou) até o prazo. A
  # execução foi lida antes da troca, com o `due_at` da espera. Resposta depois do prazo não conta: o prazo venceu.
  #
  # A volta ao mesmo "esperar até" na mesma rodada (o laço dos documentos, G46) começa no instante em que ele foi
  # cumprido, não agora: a 2ª e a 3ª foto que chegaram enquanto a IA lia a 1ª (a execução andando, sem ninguém para
  # acordar) contam, e o laço roda de novo para elas.
  def janela_da_espera(passo)
    return Duracao.janela(passo['prazo'], @execucao.due_at) if @retomando

    @cumprida_em&.key?(passo['id']) ? (@cumprida_em[passo['id']]..) : Duracao.janela(passo['prazo'], nil)
  end

  def cumprida(passo)
    (@cumprida_em ||= {})[passo['id']] = Time.current
    registrar(passo['id'], 'ok').then { @roteiro.seguinte(passo['id']) }
  end
end

# Os passos novos com motor (#2932–#2934) no Executor, e o "usar outra automação" (#2933), que espera o bloco.
#
# Sem a flag `automacao_passos_novos` (rollback), a execução que chega num deles para ali, com o motivo, e a filha da
# lista ou a execução do bloco já abertas param na reconferência (Executor#impedimento, `flag_desligada`): nada dos
# passos novos roda pela metade. O "para cada" e o "buscar em outro sistema" seguem pela porta da ação (PassoDeAcao); o "usar
# outra automação" fica aqui, porque espera.
#
# O "usar outra automação" (ver Bloco):
# - ao chegar, confere tudo como na ação e abre a execução do bloco (PassoUsarBloco). A mãe grava o registro e passa a
#   esperar no passo ANTES de a execução do bloco ir para a fila: se o bloco terminasse antes, não teria quem acordar;
# - ao voltar (o bloco acordou a mãe, ou a conferência do dia): o bloco ainda andando, espera de novo; terminou bem,
#   segue; falhou ou foi interrompido, a mãe falha com o motivo; parou (desligado, pausado), a mãe para.
module Autonomia::Automacao::BlocoNoExecutor
  # O estado final da execução do bloco => [estado da mãe, motivo, resultado do registro]. `concluida` segue.
  FINAIS = { 'falhou' => %w[falhou bloco_falhou falhou], 'interrompida' => %w[falhou bloco_falhou falhou],
             'parada' => %w[parada bloco_parou pulado] }.freeze

  private

  # A flag que é o rollback do que esta execução faz, desligada: o motivo, ou nil.
  # - #2499: a dos gatilhos de card é o rollback da F6; a execução aberta de gatilho de card fecha.
  # - #2932–#2934: a dos passos novos; a filha da lista e a execução do bloco já abertas também param: os passos delas
  #   são comuns, e só o passo novo em si pararia.
  def flag_desligada
    return 'gatilho_desligado' unless ::Autonomia::Automacao::Gatilhos.disponivel?(@execucao.chave_gatilho, @account)

    'passos_novos_desligados' if de_passo_novo_sem_flag?
  end

  # Ela, ou uma execução acima dela, nasceu de um passo novo ("para cada" ou bloco), e a flag está desligada.
  def de_passo_novo_sem_flag?
    return false if ::Autonomia::Automacao::PassosNovos.ligados?(@account)

    [@execucao, *::Autonomia::Automacao::Bloco.acima(@execucao)].any? do |uma|
      ::Autonomia::Automacao::RepetirLista.da(uma) || ::Autonomia::Automacao::Bloco.da(uma)
    end
  end

  def passo_novo(passo)
    return encerrar(passo['id'], 'parada', 'passos_novos_desligados') unless ::Autonomia::Automacao::PassosNovos.ligados?(@account)

    ::Autonomia::Automacao::Bloco.do_tipo?(passo) ? usar_bloco(passo) : acao(passo)
  end

  def usar_bloco(passo)
    reconferir
    return if impedida?(passo['id'])
    return voltar_do_bloco(passo) if @retomando

    chamada = ::Autonomia::Automacao::PassoUsarBloco.new(execucao: @execucao, passo: passo)
    resultado = chamada.chamar
    return encerrar(passo['id'], 'falhou', resultado.motivo, 'falhou', resultado.dados) if resultado.tipo == :permanente
    return seguir_depois_da_acao(passo, resultado) unless resultado.tipo == :ok

    registrar(passo['id'], 'ok', resultado.motivo, resultado.dados)
    aguardar(passo, Time.current + ::Autonomia::Automacao::Bloco::CONFERENCIA, registrar: false)
    chamada.enfileirar
    nil
  end

  def voltar_do_bloco(passo)
    filha = ::Autonomia::Automacao::PassoUsarBloco.filha_de(@execucao, passo['id'])
    return encerrar(passo['id'], 'falhou', 'bloco_sumiu', 'falhou') if filha.nil?
    return aguardar(passo, Time.current + ::Autonomia::Automacao::Bloco::CONFERENCIA, registrar: false) if filha.finalizada_em.nil?

    dados = { 'bloco_id' => filha.automacao_id, 'filha_id' => filha.id }
    estado, motivo, resultado = FINAIS[filha.estado]
    return encerrar(passo['id'], estado, motivo, resultado, dados) if estado

    registrar(passo['id'], 'ok', 'bloco_terminou', dados)
    @roteiro.seguinte(passo['id'])
  end
end

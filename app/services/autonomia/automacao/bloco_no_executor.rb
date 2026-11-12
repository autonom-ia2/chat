# Os passos novos com motor (#2932–#2934) no Executor, e o "usar outra automação" (#2933), que espera o bloco.
#
# Sem a flag `automacao_passos_novos` (rollback), a execução que chega num deles para ali, com o motivo: nada dos passos
# novos roda pela metade. O "para cada" e o "buscar em outro sistema" seguem pela porta da ação (PassoDeAcao); o "usar
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

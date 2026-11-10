# G65 (#2842) no Executor: o passo da filha do "em outro registro" lê o registro de origem (`origem.*`), e quem ligou
# deixou de alcançá-lo entre a mãe e a filha (perdeu o funil do João, a conversa dele). O passo pula com o motivo
# próprio, sem ler nada da origem, e a filha segue para o passo seguinte. A pergunta é a mesma do impedimento
# (Acesso#alcanca?, pelo Contexto#origem_fora_do_alcance?); o Valores lê vazio do mesmo jeito (Contexto#origem).
#
# O "se" (e o "esperar até") cuja condição lê `origem.*` é pulado inteiro, com os ramos: sem a origem não dá para
# decidir o ramo, e pular é o lado seguro (decisão da revisão do #2675).
module Autonomia::Automacao::OrigemNoExecutor
  private

  def sem_origem?(passo) = ::Autonomia::Automacao::Valores::Origem.no_passo?(passo) && contexto.origem_fora_do_alcance?

  # Reconfere antes, como a ação: a automação desligada ou quem ligou sem acesso param antes do pulo.
  def pular_sem_origem(passo)
    @passo_atual = passo['id']
    reconferir
    return if impedida?(passo['id'])

    registrar(passo['id'], 'pulado', 'origem_fora_do_alcance')
    @roteiro.seguinte(passo['id'])
  end
end

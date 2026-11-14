# "Trazer minha lista" (#2896): o "Desfazer" de uma lista, em segundo plano (Relacionamentos::Trazer::Desfazer). A
# requisição já deixou a importação "desfazendo" e põe este job na fila depois que a transação dela termina.
#
# Repetir o job não faz nada: ele só roda com o desfazer `processing`, e o que já foi desfeito fica marcado. O desfazer
# que quebra fica `failed` e o erro sobe; a repetição da fila encontra `failed` e sai, sem laço. Quem decide tentar de
# novo é a pessoa, na tela.
#
# quem: a pessoa que pediu (só o id vai na fila), para a Auditoria de quem foi apagado.
class Relacionamentos::Trazer::DesfazerJob < ApplicationJob
  queue_as :low

  def perform(importacao, quem = nil)
    Relacionamentos::Trazer::Desfazer.new(importacao, quem: quem).call
  end
end

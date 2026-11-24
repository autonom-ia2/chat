# Quantas revisões de conversas rodam ao mesmo tempo (#3158, B8b): uma por conta e três na instalação inteira.
# Chaves próprias (`autonomia:guide:revisoes:*`), de propósito: uma revisão não toma a vaga de uma tarefa de escrita
# (`Tarefas::Semaforo`, mais três), e a instalação tem até seis trabalhos longos de IA do Guia ao mesmo tempo.
module Autonomia::Guide::Revisoes::Semaforo
  PREFIXO = 'autonomia:guide:revisoes'.freeze
  TOTAL = 3
  VAGAS = ::Autonomia::Guide::Vagas.new(PREFIXO, total: TOTAL)

  module_function

  def entrar(revisao) = VAGAS.entrar(revisao)
  def sair(revisao) = VAGAS.sair(revisao)
end

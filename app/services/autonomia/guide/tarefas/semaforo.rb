# Quantas tarefas longas rodam ao mesmo tempo (#936): uma por conta e três na instalação inteira.
#
# A vaga é da tarefa enquanto ela anda (entre um lote e outro também) e vence sozinha se o processo
# morrer sem devolver: a validade é renovada a cada lote. A tarefa que não consegue vaga fica na fila.
# A conta das vagas é a `Autonomia::Guide::Vagas`, que a revisão de conversas (#3158) usa com chaves próprias.
module Autonomia::Guide::Tarefas::Semaforo
  PREFIXO = 'autonomia:guide:tarefas'.freeze
  POR_CONTA = "#{PREFIXO}:conta:".freeze
  RODANDO = "#{PREFIXO}:rodando".freeze
  TRAVA = "#{PREFIXO}:semaforo".freeze
  TOTAL = 3
  VALIDADE = ::Autonomia::Guide::Vagas::VALIDADE
  VAGAS = ::Autonomia::Guide::Vagas.new(PREFIXO, total: TOTAL)

  module_function

  # -> true quando a tarefa tem (ou renovou) a vaga.
  def entrar(tarefa) = VAGAS.entrar(tarefa)
  def sair(tarefa) = VAGAS.sair(tarefa)
  def reservar(id, account_id) = VAGAS.reservar(id, account_id)
end

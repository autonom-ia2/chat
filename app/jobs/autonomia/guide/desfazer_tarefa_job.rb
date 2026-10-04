# "Desfazer tudo" de uma tarefa longa do Guia (#936), fora da requisição: centenas de registros não
# cabem nos 15 s do servidor. A tela acompanha o progresso pela tarefa.
class Autonomia::Guide::DesfazerTarefaJob < ApplicationJob
  queue_as :guia_tarefas

  def perform(tarefa_id)
    tarefa = ::Autonomia::Guide::Tarefa.find_by(id: tarefa_id, status: ::Autonomia::Guide::Tarefa::DESFAZENDO)
    ::Autonomia::Guide::Tarefas::DesfazerTudo.new(tarefa).perform if tarefa
  end
end

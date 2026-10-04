# Tarefas longas do Guia (#936): uma receita aplicada item a item, em lotes, com amostra antes,
# pausa de segurança depois do primeiro lote e "Desfazer tudo".
module Autonomia::Guide::Tarefas
  # O pedido não vira tarefa: o motivo, em pt-BR, volta ao modelo para ele dizer à pessoa.
  Recusada = Class.new(StandardError)
end

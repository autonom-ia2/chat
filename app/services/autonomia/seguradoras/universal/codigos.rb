# Os códigos que a Universal devolve ao nosso cliente HTTP. São os valores de `motivo` do acesso
# (Autonomia::Agents::AcessoDaSeguradora) e os códigos de erro do cliente. Só constantes.
module Autonomia::Seguradoras::Universal::Codigos
  ACESSO_RECUSADO = 'acesso_recusado'.freeze
  PEDIDO_INVALIDO = 'pedido_invalido'.freeze
  INDISPONIVEL = 'indisponivel'.freeze
  TODOS = [ACESSO_RECUSADO, PEDIDO_INVALIDO, INDISPONIVEL].freeze
end

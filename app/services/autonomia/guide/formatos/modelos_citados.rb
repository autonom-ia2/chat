# Os modelos que um trecho de controller cita (#900): `Current.account.crm_cards`
# e a constante de modelo (`policy_scope(::Crm::Card)`). É daqui que sai o
# modelo do recurso quando o `wrap_parameters` não o deduz pelo nome.
module Autonomia::Guide::Formatos::ModelosCitados
  module_function

  # O modelo da associação da conta que o nó lê, ou nil.
  def da_conta(node)
    return unless conta?(node.receiver)

    associacao = Account.reflect_on_association(node.name)
    associacao.klass if associacao && !associacao.polymorphic?
  rescue NameError
    nil
  end

  # O modelo que a constante nomeia, resolvida onde o código está, ou nil.
  def da_constante(node, modulo)
    valor = modulo.const_get(node.slice.delete_prefix('::'))
    valor if valor.is_a?(Class) && valor < ApplicationRecord && !valor.abstract_class?
  rescue NameError, ArgumentError
    nil
  end

  def conta?(node)
    case node
    when Prism::CallNode
      (node.name == :account && node.receiver.is_a?(Prism::ConstantReadNode) && node.receiver.name == :Current) ||
        (node.name == :current_account && node.receiver.nil?)
    when Prism::InstanceVariableReadNode then node.name == :@current_account
    else false
    end
  end
end

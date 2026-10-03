# Diz se um método é só um montador de parâmetros — o único tipo de método
# que o `Espiao` aceita executar (#900).
#
# O critério é o valor de retorno: a última expressão é o próprio `permit`
# (ou uma cadeia sobre ele), ou uma variável local que recebeu o `permit`.
#
#   def automation_rules_permit = params.permit(...)               # executa
#   def agent_params; attrs = params.require(:agent).permit(...); ...; attrs; end  # executa
#   def create_voice_channel; voice_params = ...permit(...); account.create!(voice_params); end  # NÃO
#
# Método que usa o `permit` para fazer outra coisa — criar canal, chamar a
# Meta no cadastro do WhatsApp — nunca roda aqui, nem desfeito no fim.
module Autonomia::Guide::Formatos::Construtor
  module_function

  def montador?(definicao)
    ultima = ultima_expressao(definicao.body)
    return false unless ultima
    return permit_na_cadeia?(ultima) if ultima.is_a?(Prism::CallNode)
    return false unless ultima.is_a?(Prism::LocalVariableReadNode)

    atribuicoes(definicao.body, ultima.name).any? { |valor| permit_na_cadeia?(valor) }
  end

  def ultima_expressao(corpo)
    corpo = corpo.statements if corpo.is_a?(Prism::BeginNode)
    corpo.is_a?(Prism::StatementsNode) ? corpo.body.last : corpo
  end

  def permit_na_cadeia?(node)
    while node.is_a?(Prism::CallNode)
      return true if node.name == :permit

      node = node.receiver
    end
    false
  end

  def atribuicoes(corpo, nome)
    pilha = [corpo]
    valores = []
    until pilha.empty?
      node = pilha.pop
      valores << node.value if node.is_a?(Prism::LocalVariableWriteNode) && node.name == nome
      pilha.concat(node.compact_child_nodes)
    end
    valores
  end
end

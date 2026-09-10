# A CHAMADA PAGA SAIU E NINGUÉM DISSE SE VALEU (entrega 5).
#
# Uma ferramenta assíncrona levanta isto de dentro do `start` quando a falha veio DEPOIS de a
# chamada ao portal sair — timeout, 502/503, resposta ilegível — e o portal não disse "não fiz".
# É diferente de toda outra exceção do `start`, e o `AsyncRunJob` trata diferente: a intenção de
# submeter FICA anotada, e a passada seguinte repete no máximo mais uma vez, marcada como
# possivelmente duplicada. Qualquer outro erro apaga a intenção — o portal disse que não cotou, ou
# nem chegou a ser chamado.
#
# `motivo` é NOSSO (a categoria do erro do connector, ou o nome de uma classe): nunca texto do
# portal, que pode carregar requisição assinada. A exceção original fica em `cause`.
class Autonomia::Agents::Tools::Native::EnvioIncerto < StandardError
  attr_reader :motivo

  def initialize(motivo)
    @motivo = motivo.to_s
    super("envio incerto: #{@motivo}")
  end
end

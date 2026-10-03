# `params` vazio que anota o que o controller pede a ele (#900).
#
# É uma subclasse, e não um `prepend` em `ActionController::Parameters`: o
# espião só existe na instância que o `Espiao` entrega ao controller isolado, e
# nenhuma requisição de verdade passa por ele.
#
# `require` não levanta `ParameterMissing`: devolve outro espião, com o
# envelope no caminho, para o `permit` seguinte ser anotado no lugar certo.
class Autonomia::Guide::Formatos::ParametrosEspiao < ActionController::Parameters
  attr_reader :registro

  def initialize(parameters = {}, logging_context = {}, registro: [], caminho: [])
    super(parameters, logging_context)
    @registro = registro
    @caminho = caminho
  end

  def permit(*filtros)
    @registro << [@caminho, filtros]
    ActionController::Parameters.new({}).permit!
  end

  def require(chave)
    self.class.new(registro: @registro, caminho: @caminho + [chave.to_s])
  end
  alias required require

  # `params[:assistant][:config]` não pode estourar em nil antes do `permit`
  # que interessa: a leitura devolve outro espião, vazio.
  def [](chave)
    self.class.new(registro: @registro, caminho: @caminho + [chave.to_s])
  end
end

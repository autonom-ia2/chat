# Executa SÓ o método que monta os parâmetros permitidos, numa instância
# isolada do controller, para saber o que o código não diz (#900).
#
# `permit(*inbox_attributes, channel: [:type, *channel_attributes])` e
# `permit(*permitted_attributes, ...)` não se resolvem lendo: dependem de
# método, de variável e até da conta. Aqui o método roda com um `params`
# espião (`ParametrosEspiao`), sem requisição, e a conta é um `Account.new` que
# nunca é salvo. Duas contas: uma sem recurso nenhum ligado e outra com todos
# — o campo que só aparece na segunda depende de recurso da conta
# (`execution_delay` só existe com automação com atraso ligada).
#
# O que nunca roda aqui: a action em si e os `before_action`. Esses mudam o
# banco; o método de params só lê. Mesmo assim tudo roda numa transação
# desfeita no fim, e qualquer erro vira "não resolvido", nunca um chute.
class Autonomia::Guide::Formatos::Espiao
  Parametros = ::Autonomia::Guide::Formatos::ParametrosEspiao

  def initialize(klass)
    @klass = klass
  end

  # Os `permit` que o método faz, como `[[caminho, filtros], ...]`, ou nil se
  # não deu para executar.
  def permits(metodo, conta:, argumentos: [])
    return unless executavel?(metodo, argumentos)

    registro = []
    controller = @klass.new
    controller.params = Parametros.new(registro: registro)
    controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for('/'))
    com_conta(conta) { desfazendo { controller.send(metodo, *argumentos) } }
    registro
  rescue StandardError
    nil
  end

  def self.conta_sem_recursos
    Account.new
  end

  def self.conta_com_recursos
    Account.new.tap { |conta| conta.enable_features(*Featurable::FEATURE_LIST.pluck('name')) }
  end

  private

  # Só montador de parâmetros (`Construtor`), e sem argumento obrigatório: os
  # argumentos de quem chama são justamente o que não se sabe aqui.
  def executavel?(metodo, argumentos)
    unbound = @klass.instance_method(metodo)
    definicao = ::Autonomia::Guide::Formatos::Fontes.definicao(unbound)
    return false unless definicao && ::Autonomia::Guide::Formatos::Construtor.montador?(definicao)

    unbound.parameters.count { |tipo, _| %i[req keyreq].include?(tipo) } <= argumentos.size
  rescue NameError
    false
  end

  def com_conta(conta)
    anterior = [Current.account, Current.user, Current.account_user]
    Current.account = conta
    Current.user = nil
    Current.account_user = nil
    yield
  ensure
    Current.account, Current.user, Current.account_user = anterior
  end

  def desfazendo
    ActiveRecord::Base.transaction(requires_new: true) do
      yield
      raise ActiveRecord::Rollback
    end
  end
end

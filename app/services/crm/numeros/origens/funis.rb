# O funil de Números › "De onde vieram os clientes" (#2001, F6 do #1871). A escolha segue o acesso da pessoa no painel
# (Crm::Access::VisiblePipelines#apply_to_reports): a gestora que só cuida de Vendas só escolhe Vendas. "Todos os funis"
# só para quem vê todos os funis ativos da conta; quem não vê e pede "todos" (link de outra pessoa) fica no principal.
# Funil que a pessoa não vê, ou que não existe, é recusado (ForaDoAcesso, 403).
#
# Sem pedido, o funil principal: o padrão da conta, senão o primeiro da ordem que a pessoa vê.
class Crm::Numeros::Origens::Funis
  TODOS = 'todos'.freeze

  attr_reader :escolhido

  class ForaDoAcesso < StandardError; end

  def initialize(account:, acesso:, pedido: nil)
    @account = account
    @visiveis = acesso.apply_to_reports(account.crm_pipelines.active).order(is_default: :desc, position: :asc, id: :asc).to_a
    @escolhido = escolher(pedido.to_s)
  end

  def nenhum?
    @visiveis.empty?
  end

  def todos?
    @escolhido.nil? && !nenhum?
  end

  def ve_todos?
    return @ve_todos if defined?(@ve_todos)

    @ve_todos = !nenhum? && @visiveis.size == @account.crm_pipelines.active.count
  end

  def ids
    todos? ? @visiveis.map(&:id) : [@escolhido&.id].compact
  end

  def principal
    @visiveis.first
  end

  def payload
    {
      escolhido: todos? ? TODOS : @escolhido&.id&.to_s, nome: @escolhido&.name,
      opcoes: @visiveis.map { |funil| { id: funil.id.to_s, nome: funil.name, principal: funil == principal } } +
        (ve_todos? ? [{ id: TODOS, nome: nil, principal: false }] : [])
    }
  end

  private

  def escolher(pedido)
    return principal if pedido.blank? || (pedido == TODOS && !ve_todos?)
    return nil if pedido == TODOS

    @visiveis.find { |funil| funil.id.to_s == pedido } || raise(ForaDoAcesso)
  end
end

# Os passos que se conferem sozinhos ao salvar, cada um na própria classe (saiu da Receita quando ela passou do tamanho,
# no G18): o "Passar para a agente de IA" (G15), o "criar card" (G4), que confere também a pessoa, a campanha (G14), que
# confere o gatilho, a pessoa e a campanha da tela, o "criar retorno" (G3) e o "em outro registro" (G18). Os caminhos
# que o retorno e o "em outro registro" leem passam pela régua da Receita (o bloco `caminho`).
class Autonomia::Automacao::PassosProprios
  TIPOS = %w[ia_assumir card campanha retorno em_outro_registro].freeze

  def self.do_tipo?(passo) = TIPOS.include?(passo['tipo'])

  # `dentro`: a receita é o ramo de um "em outro registro" (Receita com `alvo`). `caminho`: (id do passo, caminho) →
  # problemas, a régua da Receita.
  def initialize(conta:, account_user:, receita:, dentro:, &caminho)
    @conta = conta
    @account_user = account_user
    @receita = receita
    @dentro = dentro
    @caminho = caminho
  end

  def problemas(passo)
    case passo['tipo']
    when 'card' then ::Autonomia::Automacao::PassoDeCard.problemas_ao_salvar(@conta, passo, @account_user)
    when 'campanha'
      ::Autonomia::Automacao::PassoDeCampanha.problemas_ao_salvar(passo, @receita, conta: @conta, account_user: @account_user)
    when 'retorno' then retorno(passo)
    when 'em_outro_registro' then outro_registro(passo)
    else ::Autonomia::Automacao::PassoDeIaAssumir.problemas_ao_salvar(@conta, passo)
    end
  end

  private

  def retorno(passo)
    ::Autonomia::Automacao::PassoDeRetorno.problemas_ao_salvar(@conta, passo, @receita, @account_user) { |c| @caminho.call(passo['id'], c) }
  end

  def outro_registro(passo)
    ::Autonomia::Automacao::EmOutroRegistro.problemas_ao_salvar(passo, conta: @conta, account_user: @account_user, dentro: @dentro) do |c|
      @caminho.call(passo['id'], c)
    end
  end
end

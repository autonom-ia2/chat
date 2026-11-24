# Os dados do cupom no texto do passo "Mandar cupom" (#3100): o código da pessoa, o que o cupom dá e até quando vale.
# Só existem dentro desse passo, que acabou de achar ou sortear o código (Autonomia::Automacao::PassoDeMandarCupom); o
# resto dos dados (o nome do contato, o saldo do cartão) segue pelos valores de sempre da execução.
class Fidelidade::ValoresDoCupom < SimpleDelegator
  CODIGO = 'cupom.codigo'.freeze
  OFERTA = 'cupom.oferta'.freeze
  VALE_ATE = 'cupom.vale_ate'.freeze
  CAMINHOS = [CODIGO, OFERTA, VALE_ATE].freeze

  def self.do_cupom?(caminho) = caminho.to_s.start_with?('cupom.')

  # `valores`: os da execução (Autonomia::Automacao::Valores). `codigo`: o Fidelidade::CupomCodigo da pessoa.
  # `vale_ate`: até quando vale (o do código, ou o que ele vai ganhar ao chegar).
  def initialize(valores, codigo:, vale_ate:)
    super(valores)
    @codigo = codigo
    @vale_ate = vale_ate
  end

  def ler(caminho)
    case caminho
    when CODIGO then @codigo.codigo
    when OFERTA then Fidelidade::TextoDoCupom.oferta(@codigo.cupom, conta)
    when VALE_ATE then Fidelidade::TextoDoCupom.data(@vale_ate, conta)
    else __getobj__.ler(caminho)
    end
  end

  private

  def conta = @codigo.cupom.account
end

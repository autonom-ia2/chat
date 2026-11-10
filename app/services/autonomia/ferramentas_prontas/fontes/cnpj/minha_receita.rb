# O CNPJ na Minha Receita (primeira reserva), no formato da Receita.
class Autonomia::FerramentasProntas::Fontes::Cnpj::MinhaReceita < Autonomia::FerramentasProntas::Provedor
  include Autonomia::FerramentasProntas::Fontes::Cnpj::FormatoDaReceita

  NOME = 'minhareceita'.freeze
  HOST = 'minhareceita.org'.freeze

  private

  def caminho(cnpj)
    "/#{cnpj}"
  end
end

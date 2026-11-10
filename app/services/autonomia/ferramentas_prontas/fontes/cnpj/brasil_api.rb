# O CNPJ na BrasilAPI (principal), no formato da Receita.
class Autonomia::FerramentasProntas::Fontes::Cnpj::BrasilApi < Autonomia::FerramentasProntas::Provedor
  include Autonomia::FerramentasProntas::Fontes::Cnpj::FormatoDaReceita

  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  private

  def caminho(cnpj)
    "/api/cnpj/v1/#{cnpj}"
  end
end

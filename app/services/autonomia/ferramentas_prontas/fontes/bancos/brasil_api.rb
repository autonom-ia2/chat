# O banco na BrasilAPI (principal).
class Autonomia::FerramentasProntas::Fontes::Bancos::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(_consulta, params)
    codigo = params.fetch('codigo')
    dado = objeto!(get("/api/banks/v1/#{codigo.to_i}"))
    Autonomia::FerramentasProntas::Fontes::Bancos.banco(
      codigo: codigo, nome: exigir!(texto(dado['name'])), nome_completo: texto(dado['fullName']), ispb: texto(dado['ispb'])
    )
  end
end

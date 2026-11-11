# O CEP na BrasilAPI (principal). CEP que não existe: 404, que o cliente HTTP lê como `NaoEncontrado`.
class Autonomia::FerramentasProntas::Fontes::Cep::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  # Só do CEP para o endereço: a BrasilAPI não busca o CEP pela rua.
  def self.aplica?(consulta, _params)
    consulta.nome == 'endereco'
  end

  def consultar(_consulta, params)
    dado = objeto!(get("/api/cep/v2/#{params['cep']}"))
    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['street']), bairro: texto(dado['neighborhood']),
      cidade: exigir!(texto(dado['city'])), uf: exigir!(texto(dado['state']))
    )
  end
end

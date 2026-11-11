# O CEP na BrasilAPI (principal). CEP que não existe: 404, que o cliente HTTP lê como `NaoEncontrado`.
# A BrasilAPI v2 junta várias bases e diz de qual veio (`service`). O open-cep é base aberta, editável, e devolveu
# endereço para o CEP que não existe (99999-999 em Sarandi, varredura F01, quando o ViaCEP dizia que não existe): o
# endereço dele não vale aqui. Fica "não tem" da BrasilAPI, e o ViaCEP decide.
class Autonomia::FerramentasProntas::Fontes::Cep::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze
  BASE_ABERTA = 'open-cep'.freeze

  # Só do CEP para o endereço: a BrasilAPI não busca o CEP pela rua.
  def self.aplica?(consulta, _params)
    consulta.nome == 'endereco'
  end

  def consultar(_consulta, params)
    dado = objeto!(get("/api/cep/v2/#{params['cep']}"))
    raise NaoEncontrado if dado['service'].to_s.strip.casecmp?(BASE_ABERTA)

    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['street']), bairro: texto(dado['neighborhood']),
      cidade: exigir!(texto(dado['city'])), uf: exigir!(texto(dado['state']))
    )
  end
end

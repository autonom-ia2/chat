# O CEP na AwesomeAPI: a 1ª reserva do endereço pelo CEP (#2906; decisão do Rodrigo, 11/11/2026: "bom ter os dois ou
# mais, para termos margem de rate limit"). CEP que não existe: 404 `{"code":"not_found"}`, que o cliente HTTP lê como
# `NaoEncontrado`. A resposta traz também latitude, longitude, DDD e o código IBGE: nada disso vai ao agente.
#
# Chave gratuita opcional (100 mil pedidos por mês, no cabeçalho `x-api-key`): sem ela, o provedor funciona igual. Só o
# nome da variável fica no código. O teto global acompanha (`TetoDoProvedor.tetos`).
class Autonomia::FerramentasProntas::Fontes::Cep::AwesomeApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'awesomeapi'.freeze
  HOST = 'cep.awesomeapi.com.br'.freeze
  CHAVE = 'AUTONOMIA_AWESOMEAPI_CHAVE'.freeze

  # Só do CEP para o endereço: a AwesomeAPI não busca o CEP pela rua.
  def self.aplica?(consulta, _params)
    consulta.nome == 'endereco'
  end

  def self.chave
    chave_do_ambiente(CHAVE)
  end

  def self.cabecalhos
    chave ? { 'x-api-key' => chave } : {}
  end

  def consultar(_consulta, params)
    dado = objeto!(get("/json/#{params['cep']}"))

    Autonomia::FerramentasProntas::Fontes::Cep.enxuto(
      cep: params['cep'], logradouro: texto(dado['address']), bairro: texto(dado['district']),
      cidade: exigir!(texto(dado['city'])), uf: exigir!(texto(dado['state']))
    )
  end
end

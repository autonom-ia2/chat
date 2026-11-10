# O DDD na BrasilAPI (principal): estado e cidades.
class Autonomia::FerramentasProntas::Fontes::Ddd::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(_consulta, params)
    ddd = params.fetch('ddd')
    dado = objeto!(get("/api/ddd/v1/#{ddd}"))
    uf = exigir!(texto(dado['state']))&.upcase
    raise Falha, 'resposta_invalida' unless Autonomia::FerramentasProntas::Ufs.nome(uf)

    cidades = lista!(dado['cities']).filter_map { |nome| texto(nome) }.sort_by { |nome| Autonomia::FerramentasProntas::Lista.comparavel(nome) }
    Autonomia::FerramentasProntas::Fontes::Ddd.resposta(ddd, uf, cidades: exigir!(cidades))
  end
end

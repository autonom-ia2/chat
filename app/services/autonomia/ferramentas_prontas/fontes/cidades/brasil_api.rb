# Estados e municípios na BrasilAPI (reserva; ela repassa o IBGE). Os municípios só respondem, em 10/11/2026, com os três
# provedores dela no pedido (com um só, 504); o da Wikipédia põe o estado entre parênteses em alguns nomes
# ("CAPIXABA (ACRE)"), e esse sufixo sai.
class Autonomia::FerramentasProntas::Fontes::Cidades::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    return estados if consulta.nome == 'estados'

    uf = params.fetch('uf').upcase
    lista = lista!(get("/api/ibge/municipios/v1/#{uf}?providers=dados-abertos-br,gov,wikipedia"))
    estado = Autonomia::FerramentasProntas::Ufs.nome(uf)
    sufixos = [estado.upcase, I18n.transliterate(estado).upcase].uniq.map { |nome| " (#{nome})" }
    nomes = lista.map { |item| sufixos.reduce(exigir!(texto(objeto!(item)['nome']))) { |nome, sufixo| nome.delete_suffix(sufixo) } }
    Autonomia::FerramentasProntas::Fontes::Cidades.cidades(uf, exigir!(nomes))
  end

  private

  def estados
    Autonomia::FerramentasProntas::Fontes::Cidades.estados(exigir!(lista!(get('/api/ibge/uf/v1'))))
  end
end

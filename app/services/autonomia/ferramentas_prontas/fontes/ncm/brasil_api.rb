# A NCM na BrasilAPI (fonte única). Código que não existe: 404, lido como `NaoEncontrado`. Busca sem resultado: lista
# vazia, também "não encontrado".
class Autonomia::FerramentasProntas::Fontes::Ncm::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    ncm = Autonomia::FerramentasProntas::Fontes::Ncm
    return ncm.item(objeto!(get("/api/ncm/v1/#{params.fetch('codigo')}"))) if consulta.nome == 'codigo'

    busca = params.fetch('busca')
    achados = lista!(get("/api/ncm/v1?search=#{codificar(busca)}", max_bytes: ncm::MAX_BYTES_BUSCA))
    itens = achados.select { |dado| ncm.vigente?(dado) }.map { |dado| ncm.item(dado) }
    raise NaoEncontrado if itens.empty?

    ncm.lista(busca, itens)
  end
end

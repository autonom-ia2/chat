# A NCM na BrasilAPI (fonte única). Código de 2 ou 4 dígitos que não existe: 404, lido como `NaoEncontrado`. O de 8
# dígitos vem da busca pela posição dele ("search=0901"), uma chamada só; fora dela, também "não encontrado". Busca sem
# resultado: lista vazia, "não encontrado". Toda consulta é uma chamada só.
class Autonomia::FerramentasProntas::Fontes::Ncm::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  def consultar(consulta, params)
    consulta.nome == 'codigo' ? codigo(params.fetch('codigo')) : buscar(params.fetch('busca'))
  end

  private

  def ncm
    Autonomia::FerramentasProntas::Fontes::Ncm
  end

  # Pelo código de um grupo: uma chamada pela posição dele (a BrasilAPI não acha "9503.00.3", e "0901.2" vem sem o 09.01,
  # que diz o material). Por palavra: o que a fonte trouxe.
  def buscar(busca)
    grupo = ncm.grupo_da_busca(busca)
    return ncm.do_grupo(busca, grupo, procurar(ncm.prefixo_da_busca(grupo))) if grupo

    achados = procurar(busca)
    raise NaoEncontrado if achados.empty?

    ncm.lista(busca, ncm.niveis(achados))
  end

  # O de 8 dígitos numa chamada só, pela posição dele, que já traz o código e os níveis de cima. O de 2 e o de 4 já
  # têm o texto inteiro.
  def codigo(codigo)
    return ncm.da_nota(codigo, procurar(ncm.prefixo_da_busca(codigo))) if codigo.length == ncm::DA_NOTA

    ncm.do_codigo(ncm.item(ncm::Nivel.de(objeto!(get("/api/ncm/v1/#{codigo}")))), codigo)
  end

  # Os itens vigentes de uma busca na fonte (palavra ou parte do código).
  def procurar(texto)
    lista!(get("/api/ncm/v1?search=#{codificar(texto)}", max_bytes: ncm::MAX_BYTES_BUSCA)).select { |dado| ncm.vigente?(dado) }
  end
end

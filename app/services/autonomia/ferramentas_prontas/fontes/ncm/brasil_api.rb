# A NCM na BrasilAPI (fonte única). Código de 2 ou 4 dígitos que não existe: 404, lido como `NaoEncontrado`. O de 8
# dígitos vem da busca pela posição dele ("search=0901"), uma chamada só; fora dela, também "não encontrado". Busca sem
# resultado: lista vazia, "não encontrado". A busca faz no máximo uma chamada a mais, pela posição do grupo que achou.
class Autonomia::FerramentasProntas::Fontes::Ncm::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  # Sem cache a resposta incompleta: a próxima consulta tenta a chamada a mais de novo.
  def self.validade_da_resposta(dados)
    dados['observacao'].to_s.include?(Autonomia::FerramentasProntas::Fontes::Ncm::NAO_VIERAM) ? 0 : validade
  end

  def consultar(consulta, params)
    consulta.nome == 'codigo' ? codigo(params.fetch('codigo')) : buscar(params.fetch('busca'))
  end

  private

  def ncm
    Autonomia::FerramentasProntas::Fontes::Ncm
  end

  # O grupo que abre sozinho (o "Café torrado:", 0901.2) abre nos códigos de 8 dígitos dele.
  def buscar(busca)
    achados = procurar(busca)
    raise NaoEncontrado if achados.empty?

    niveis = ncm.niveis(achados)
    grupo = ncm.grupo_a_abrir(busca, niveis)
    return ncm.sem_abrir(busca, niveis, grupo) if grupo.nil? || grupo == ncm::EMPATE

    ncm.aberta(busca, niveis, grupo, descendentes(busca, grupo, achados))
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

  # A busca que já foi pela posição do grupo ("0901") já trouxe os filhos dele: sem chamada a mais.
  def descendentes(busca, grupo, achados)
    prefixo = ncm.prefixo_da_busca(grupo.codigo)
    return achados if busca == prefixo

    a_tempo { procurar(prefixo) }
  end

  # A chamada a mais. O prazo da consulta acabou, ou a fonte falhou nela: nil, e fica o que a primeira trouxe, com a
  # observação ao modelo (não "não consegui": a primeira resposta é boa). A fonte sem nada: lista vazia.
  def a_tempo
    yield
  rescue NaoEncontrado
    []
  rescue Falha
    nil
  end
end

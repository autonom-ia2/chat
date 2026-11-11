# A NCM na BrasilAPI (fonte única). Código que não existe: 404, lido como `NaoEncontrado`. Busca sem resultado: lista
# vazia, também "não encontrado". No máximo uma chamada a mais por consulta, pela posição do código ("search=0901"): os
# códigos de 8 dígitos do grupo que a busca achou, ou os níveis de cima do código pedido, para a descrição completa.
class Autonomia::FerramentasProntas::Fontes::Ncm::BrasilApi < Autonomia::FerramentasProntas::Provedor
  NOME = 'brasilapi'.freeze
  HOST = 'brasilapi.com.br'.freeze

  # Sem cache a resposta incompleta: a próxima consulta tenta a chamada a mais de novo.
  def self.validade_da_resposta(dados)
    Autonomia::FerramentasProntas::Fontes::Ncm::INCOMPLETAS.include?(dados['observacao']) ? 0 : validade
  end

  def consultar(consulta, params)
    consulta.nome == 'codigo' ? codigo(params.fetch('codigo')) : buscar(params.fetch('busca'))
  end

  private

  def ncm
    Autonomia::FerramentasProntas::Fontes::Ncm
  end

  # O grupo mais relevante que veio (o "Café torrado:", 0901.2) abre nos códigos de 8 dígitos dele.
  def buscar(busca)
    achados = procurar(busca)
    raise NaoEncontrado if achados.empty?

    grupo = ncm.grupo_a_abrir(busca, achados)
    return ncm.lista(busca, achados) unless grupo

    ncm.aberta(busca, achados, grupo, descendentes(busca, grupo, achados))
  end

  # O de 8 dígitos sobe pela hierarquia da posição dele; o de 2 e o de 4 já têm o texto inteiro.
  def codigo(codigo)
    dado = objeto!(get("/api/ncm/v1/#{codigo}"))
    return ncm.do_codigo(ncm.item(dado), codigo) unless codigo.length == ncm::DA_NOTA

    hierarquia = a_tempo { procurar(ncm.prefixo_da_busca(codigo)) }
    return ncm.item(dado).merge('observacao' => ncm::SO_O_ULTIMO_NIVEL) if hierarquia.nil?

    ncm.item(dado, ncm::Descricao.indice(hierarquia))
  end

  # Os itens vigentes de uma busca na fonte (palavra ou parte do código).
  def procurar(texto)
    lista!(get("/api/ncm/v1?search=#{codificar(texto)}", max_bytes: ncm::MAX_BYTES_BUSCA)).select { |dado| ncm.vigente?(dado) }
  end

  # A busca que já foi pela posição do grupo ("0901") já trouxe os filhos dele: sem chamada a mais.
  def descendentes(busca, grupo, achados)
    prefixo = ncm.prefixo_da_busca(grupo['codigo'])
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

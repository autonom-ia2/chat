# As contratações publicadas na API de consulta do PNCP (fonte única), a primeira página do período. Sem compra no
# período, o PNCP responde 204 sem corpo, ou a lista vazia: "não encontrado".
class Autonomia::FerramentasProntas::Fontes::ComprasGoverno::Pncp < Autonomia::FerramentasProntas::Provedor
  NOME = 'pncp'.freeze
  HOST = 'pncp.gov.br'.freeze

  def consultar(_consulta, params)
    compras = Autonomia::FerramentasProntas::Fontes::ComprasGoverno
    municipio = exigir!(compras.municipio(params))
    codigo, modalidade = compras::MODALIDADES.fetch(params.fetch('modalidade'))
    dado = objeto!(get_vazio_e_nao_encontrado(caminho(municipio.codigo, codigo, params)))
    itens = lista!(dado['data'] || [])
    raise NaoEncontrado if itens.empty?

    { 'cidade' => municipio.nome, 'uf' => municipio.uf, 'de' => params['de'], 'ate' => params['ate'], 'modalidade' => modalidade,
      'total_no_periodo' => dado['totalRegistros'].is_a?(Integer) ? dado['totalRegistros'] : itens.size,
      'compras' => itens.map { |item| compras.compra(objeto!(item)) } }
  end

  private

  def caminho(municipio, modalidade, params)
    datas = %w[de ate].map { |campo| params.fetch(campo).delete('-') }
    "/api/consulta/v1/contratacoes/publicacao?dataInicial=#{datas.first}&dataFinal=#{datas.last}" \
      "&codigoModalidadeContratacao=#{modalidade.to_i}&codigoMunicipioIbge=#{municipio.to_i}" \
      "&pagina=1&tamanhoPagina=#{Autonomia::FerramentasProntas::Fontes::ComprasGoverno::POR_PAGINA}"
  end
end

# As contratações publicadas na API de consulta do PNCP (fonte única), a primeira página do período. Sem compra no
# período, o PNCP responde 204 sem corpo, ou a lista vazia: "não encontrado".
class Autonomia::FerramentasProntas::Fontes::ComprasGoverno::Pncp < Autonomia::FerramentasProntas::Provedor
  NOME = 'pncp'.freeze
  HOST = 'pncp.gov.br'.freeze

  # Sem cache a resposta parcial.
  def self.validade_da_resposta(dados)
    dados['parcial'] ? 0 : validade
  end

  # O período inteiro não veio no prazo (o PNCP leva mais de 10 s em cidade grande, varredura F32/F33): o último dia do
  # período, com o que sobra do prazo da consulta, em vez de "não consegui". A resposta diz que é parcial.
  def consultar(_consulta, params)
    do_periodo(params)
  rescue Falha => e
    raise unless e.motivo == 'tempo_esgotado' && params['de'] != params['ate']

    do_periodo(params.merge('de' => params['ate'])).merge('parcial' => true)
  end

  private

  def do_periodo(params)
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

  def caminho(municipio, modalidade, params)
    datas = %w[de ate].map { |campo| params.fetch(campo).delete('-') }
    "/api/consulta/v1/contratacoes/publicacao?dataInicial=#{datas.first}&dataFinal=#{datas.last}" \
      "&codigoModalidadeContratacao=#{modalidade.to_i}&codigoMunicipioIbge=#{municipio.to_i}" \
      "&pagina=1&tamanhoPagina=#{Autonomia::FerramentasProntas::Fontes::ComprasGoverno::POR_PAGINA}"
  end
end

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

    ultimo_dia(params.merge('de' => params['ate']))
  end

  private

  # O último dia sem compra não é "não tem" do período inteiro: o "não encontrado" iria ao cache por 1 hora com a chave
  # do período (revisão do #2906). Vai a resposta parcial sem compra, que não entra no cache (`validade_da_resposta`).
  def ultimo_dia(params)
    do_periodo(params).merge('parcial' => true)
  rescue NaoEncontrado
    resumo(params).merge('total_no_periodo' => 0, 'compras' => [], 'parcial' => true)
  end

  def do_periodo(params)
    dado = objeto!(get_vazio_e_nao_encontrado(caminho(params)))
    itens = lista!(dado['data'] || [])
    raise NaoEncontrado if itens.empty?

    resumo(params).merge('total_no_periodo' => dado['totalRegistros'].is_a?(Integer) ? dado['totalRegistros'] : itens.size,
                         'compras' => itens.map { |item| compras.compra(objeto!(item)) })
  end

  def resumo(params)
    municipio = exigir!(compras.municipio(params))
    { 'cidade' => municipio.nome, 'uf' => municipio.uf, 'de' => params['de'], 'ate' => params['ate'],
      'modalidade' => compras::MODALIDADES.fetch(params.fetch('modalidade')).last }
  end

  def compras
    Autonomia::FerramentasProntas::Fontes::ComprasGoverno
  end

  def caminho(params)
    municipio = exigir!(compras.municipio(params))
    modalidade = compras::MODALIDADES.fetch(params.fetch('modalidade')).first
    datas = %w[de ate].map { |campo| params.fetch(campo).delete('-') }
    "/api/consulta/v1/contratacoes/publicacao?dataInicial=#{datas.first}&dataFinal=#{datas.last}" \
      "&codigoModalidadeContratacao=#{modalidade.to_i}&codigoMunicipioIbge=#{municipio.codigo.to_i}" \
      "&pagina=1&tamanhoPagina=#{compras::POR_PAGINA}"
  end
end

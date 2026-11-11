# COMPRAS DO GOVERNO (#2858, F4): as contratações (licitações, dispensas) que os órgãos públicos de uma cidade
# publicaram no PNCP (Portal Nacional de Contratações Públicas, Lei 14.133/2021), num período e numa modalidade.
#   - a cidade vem pelo código IBGE de 7 dígitos ou pelo nome com a UF, conferidos na tabela das sedes municipais
#     (`compras_governo/municipios.rb`): cidade que não existe naquele estado é pedido inválido, e nada é consultado;
#   - a API de consulta do PNCP EXIGE a modalidade (`codigoModalidadeContratacao`) e aceita até 365 dias; aqui o período
#     vai até MAX_DIAS (a lista vem das mais antigas para as mais novas, e só a primeira página, de POR_PAGINA, é lida).
#     Sem modalidade: pregão eletrônico, a mais comum. Sem período: os últimos DIAS_PADRAO dias;
#   - a busca pela palavra no objeto da compra é LOCAL, sobre as POR_PAGINA lidas (o PNCP não busca por texto);
#   - o PNCP responde 204, sem corpo, quando não há compra no período;
#   - o link é montado aqui com o CNPJ do órgão, o ano e o número da compra (o padrão da página do edital no PNCP), e
#     não com o endereço que vem do sistema de origem.
# Fonte única: o PNCP é o portal oficial; não há reserva. Termos: dado aberto por lei (art. 174 da Lei 14.133), sem
# chave e sem limite publicado. Cache de 1 hora.
module Autonomia::FerramentasProntas::Fontes::ComprasGoverno
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MAX_DIAS = 31
  DIAS_PADRAO = 7
  POR_PAGINA = 50
  MAX_COMPRAS = 10
  MAX_OBJETO = 600
  SO_A_PRIMEIRA_PAGINA = 'O período tem %<total>d compras; olhei as %<pagina>d primeiras publicadas. Para ver as outras, ' \
                         'encurte o período.'.freeze
  LINK = 'https://pncp.gov.br/app/editais/%<cnpj>s/%<ano>d/%<sequencial>d'.freeze
  # A modalidade que o modelo escolhe -> o código e o nome no PNCP (`/api/pncp/v1/modalidades`).
  MODALIDADES = {
    'pregao_eletronico' => [6, 'Pregão eletrônico'], 'pregao_presencial' => [7, 'Pregão presencial'],
    'dispensa' => [8, 'Dispensa'], 'inexigibilidade' => [9, 'Inexigibilidade'],
    'concorrencia_eletronica' => [4, 'Concorrência eletrônica'], 'concorrencia_presencial' => [5, 'Concorrência presencial'],
    'leilao_eletronico' => [1, 'Leilão eletrônico'], 'leilao_presencial' => [13, 'Leilão presencial'],
    'credenciamento' => [12, 'Credenciamento'], 'chamada_publica' => [15, 'Chamada pública'],
    'concurso' => [3, 'Concurso'], 'dialogo_competitivo' => [2, 'Diálogo competitivo'],
    'pre_qualificacao' => [11, 'Pré-qualificação'], 'manifestacao_de_interesse' => [10, 'Manifestação de interesse']
  }.freeze

  module_function

  # O município do pedido (pelo código ou pelo nome e a UF), ou nil.
  def municipio(params)
    return Municipios.por_codigo(params['codigo_ibge']) if params['codigo_ibge']

    Municipios.buscar(params['uf'], params['cidade']) if params['cidade'] && params['uf']
  end

  # A cidade e o período. -> o nome do parâmetro que não serve, ou nil.
  def regra(params)
    return 'uf' if params['codigo_ibge'].nil? && params['cidade'] && params['uf'].nil?
    return 'cidade' if municipio(params).nil?

    de = Date.iso8601(params['de'])
    ate = Date.iso8601(params['ate'])
    'ate' if ate < de || (ate - de) >= MAX_DIAS
  end

  def data(valor)
    Autonomia::FerramentasProntas::Fontes::Feriados.data(valor)
  end

  def hoje
    Time.zone.today
  end

  # Uma compra do PNCP, enxuta: o órgão, o objeto, o valor estimado, a data e o link. Nada de quem cadastrou.
  def compra(dado)
    orgao = objeto(dado['orgaoEntidade'])
    {
      'orgao' => texto(orgao['razaoSocial']), 'unidade' => texto(objeto(dado['unidadeOrgao'])['nomeUnidade']),
      'objeto' => texto(dado['objetoCompra'])&.first(MAX_OBJETO), 'valor_estimado' => valor(dado['valorTotalEstimado']),
      'publicada_em' => data(dado['dataPublicacaoPncp'].to_s.first(10)), 'situacao' => texto(dado['situacaoCompraNome']),
      'link' => link(orgao['cnpj'], dado['anoCompra'], dado['sequencialCompra'])
    }.compact
  end

  def objeto(valor)
    valor.is_a?(Hash) ? valor : {}
  end

  def texto(valor)
    valor.to_s.squish.presence
  end

  # O PNCP manda 0 quando o valor estimado é sigiloso ou não foi informado: zero não é o valor da compra, e o campo sai.
  # A consulta de contratações não traz o indicador de sigilo (conferido em 11/11/2026 na resposta real de Uberlândia:
  # nenhum campo `orcamentoSigiloso*`); ele só existe por item, em outra chamada, e não é pedido aqui.
  def valor(numero)
    numero.to_f.round(2) if numero.is_a?(Numeric) && numero.positive?
  end

  # Só com o CNPJ de 14 dígitos e números inteiros: o resto não entra no endereço.
  def link(cnpj, ano, sequencial)
    digitos = Parametro.digitos(cnpj, 14)
    return unless digitos && ano.is_a?(Integer) && sequencial.is_a?(Integer)

    format(LINK, cnpj: digitos, ano: ano, sequencial: sequencial)
  end

  def refinar(dados, params)
    achadas = Autonomia::FerramentasProntas::Lista.filtrar(Array(dados['compras']), params['busca']) { |item| item['objeto'] }
    return if achadas.empty?

    resposta = dados.except('compras').merge(Autonomia::FerramentasProntas::Lista.cortar(achadas, 'compras', MAX_COMPRAS))
    return resposta if dados['total_no_periodo'].to_i <= POR_PAGINA

    resposta.merge('observacao' => format(SO_A_PRIMEIRA_PAGINA, total: dados['total_no_periodo'], pagina: POR_PAGINA))
  end

  CODIGO_IBGE = Parametro.new(nome: 'codigo_ibge', descricao: 'O código IBGE da cidade, 7 dígitos. Sem ele: cidade e uf.') do |valor|
    codigo = Parametro.digitos(valor, 7)
    codigo if codigo && Municipios.por_codigo(codigo)
  end
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade (com uf), quando não há o código IBGE.') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado da cidade.', opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase))
  DE = Parametro.new(nome: 'de', descricao: "A data inicial, AAAA-MM-DD. Sem data: #{DIAS_PADRAO} dias atrás.",
                     padrao: -> { (hoje - (DIAS_PADRAO - 1)).iso8601 }) { |valor| data(valor) }
  ATE = Parametro.new(nome: 'ate', descricao: "A data final, AAAA-MM-DD (até #{MAX_DIAS} dias depois da inicial). Sem data: hoje.",
                      padrao: -> { hoje.iso8601 }) { |valor| data(valor) }
  MODALIDADE = Parametro.new(nome: 'modalidade', descricao: 'O tipo de compra. Sem ele: pregão eletrônico, o mais comum.',
                             opcoes: MODALIDADES.keys, padrao: -> { 'pregao_eletronico' })
  BUSCA = Parametro.new(nome: 'busca', local: true, descricao: 'Uma palavra do que o órgão vai comprar (ex.: limpeza). Opcional.') do |valor|
    Parametro.texto_curto(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'compras_governo', slug: 'pronta_compras_governo', nome: 'Compras do governo', flag: FLAG,
    descricao: 'As compras e licitações que os órgãos públicos de uma cidade publicaram no PNCP, com órgão, objeto, ' \
               'valor estimado, data e link.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'compras', descricao: 'as compras publicadas numa cidade e num período',
        opcionais: [CODIGO_IBGE, CIDADE, UF, DE, ATE, MODALIDADE, BUSCA], provedores: [Pncp], validade: 1.hour,
        prazo_por_fonte: 8, prazo_total: 8, regra: method(:regra), refinar: method(:refinar)
      )
    ],
    limite_diario: 500,
    termos: 'PNCP (dado aberto por lei, sem chave e sem limite publicado); sem reserva. Cache de 1 hora.'
  )
end

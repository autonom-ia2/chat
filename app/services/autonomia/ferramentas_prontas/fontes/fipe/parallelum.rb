# A FIPE na parallelum (reserva; e a única com a lista de modelos e o preço por marca e modelo).
class Autonomia::FerramentasProntas::Fontes::Fipe::Parallelum < Autonomia::FerramentasProntas::Provedor
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe

  NOME = 'parallelum'.freeze
  HOST = 'parallelum.com.br'.freeze
  TIPO_NA_FONTE = { 'carros' => 'cars', 'motos' => 'motorcycles', 'caminhoes' => 'trucks' }.freeze
  # A chave gratuita (1.000 pedidos por dia em vez de 500), opcional: sem ela, a fonte funciona igual. Só o nome da
  # variável fica no código. O teto global acompanha (`TetoDoProvedor.tetos`).
  CHAVE = 'AUTONOMIA_PRONTAS_FIPE_TOKEN'.freeze

  # Colada com quebra de linha no fim, vale sem ela; com quebra no meio, não vale (seria outro cabeçalho), e a fonte
  # segue sem chave.
  def self.chave
    valor = ENV.fetch(CHAVE, nil).to_s.strip
    valor.presence unless valor.include?("\r") || valor.include?("\n")
  end

  def self.cabecalhos
    chave ? { 'X-Subscription-Token' => chave } : {}
  end

  def consultar(consulta, params)
    case consulta.nome
    when 'marcas' then Fipe.lista(exigir!(itens(base(params, '/brands'))), 'marcas', Fipe::MAX_MARCAS)
    when 'modelos' then modelos(params)
    else precos(params)
    end
  end

  private

  def base(params, resto)
    "/fipe/api/v2/#{TIPO_NA_FONTE.fetch(params['tipo'])}#{resto}"
  end

  def itens(caminho)
    lista!(get(caminho)).filter_map do |item|
      { 'codigo' => texto(item['code']), 'nome' => texto(item['name']) } if item.is_a?(Hash) && item['code'].present?
    end
  end

  # A lista inteira da marca: é ela que fica no cache. A busca pelo nome roda depois (`Fipe.refinar_modelos`).
  def modelos(params)
    { 'modelos' => exigir!(itens(base(params, "/brands/#{params['marca']}/models"))) }
  end

  # Sem o ano, os anos que existem; com ele, o preço de cada combustível daquele ano (até `MAX_ANOS_COM_PRECO`).
  def precos(params)
    do_veiculo = params['codigo_fipe'] ? "/#{params['codigo_fipe']}" : "/brands/#{params['marca']}/models/#{params['modelo']}"
    anos = itens(base(params, "#{do_veiculo}/years"))
    raise NaoEncontrado if anos.empty?
    return { 'anos_disponiveis' => anos.pluck('nome') } if params['ano'].nil?

    { 'precos' => do_ano(anos, params['ano']).map { |ano| preco_de(get(base(params, "#{do_veiculo}/years/#{ano['codigo']}"))) } }
  end

  # O código do ano vem da própria fonte e volta ao caminho: só no formato "2020-5" (dígitos, hífen, dígitos).
  def do_ano(anos, ano)
    validos = anos.select { |item| codigo_de_ano?(item['codigo']) }
    escolhidos = validos.select { |item| item['codigo'].split('-').first.to_i == ano }.first(Fipe::MAX_ANOS_COM_PRECO)
    raise NaoEncontrado if escolhidos.empty?

    escolhidos
  end

  def codigo_de_ano?(codigo)
    partes = codigo.to_s.split('-')
    partes.size == 2 && partes.all? { |parte| Autonomia::FerramentasProntas::Parametro.codigo(parte) }
  end

  def preco_de(item)
    raise Falha, 'resposta_invalida' unless item.is_a?(Hash) && item['price'].present?

    Fipe.preco(valor: item['price'], marca: item['brand'], modelo: item['model'], ano_modelo: item['modelYear'],
               combustivel: item['fuel'], codigo_fipe: item['codeFipe'], mes_de_referencia: item['referenceMonth'])
  end
end

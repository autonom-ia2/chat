# A FIPE na parallelum (reserva; e a única com a lista de modelos e o preço por marca e modelo).
class Autonomia::FerramentasProntas::Fontes::Fipe::Parallelum < Autonomia::FerramentasProntas::Provedor
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe

  NOME = 'parallelum'.freeze
  HOST = 'parallelum.com.br'.freeze
  TIPO_NA_FONTE = { 'carros' => 'cars', 'motos' => 'motorcycles', 'caminhoes' => 'trucks' }.freeze

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
    Array(get(caminho)).filter_map do |item|
      { 'codigo' => texto(item['code']), 'nome' => texto(item['name']) } if item.is_a?(Hash) && item['code'].present?
    end
  end

  # A busca é um filtro sobre a lista que a fonte devolveu: todas as palavras da busca no nome do modelo.
  def modelos(params)
    todos = exigir!(itens(base(params, "/brands/#{params['marca']}/models")))
    palavras = params['busca'].to_s.downcase.split
    achados = todos.select { |item| palavras.all? { |palavra| item['nome'].to_s.downcase.include?(palavra) } }
    raise NaoEncontrado if achados.empty?

    Fipe.lista(achados, 'modelos', Fipe::MAX_MODELOS)
  end

  # Sem o ano, os anos que existem; com ele, o preço de cada combustível daquele ano (até `MAX_ANOS_COM_PRECO`).
  def precos(params)
    do_veiculo = params['codigo_fipe'] ? "/#{params['codigo_fipe']}" : "/brands/#{params['marca']}/models/#{params['modelo']}"
    anos = itens(base(params, "#{do_veiculo}/years"))
    raise NaoEncontrado if anos.empty?
    return { 'anos_disponiveis' => anos.pluck('nome') } if params['ano'].nil?

    { 'precos' => do_ano(anos, params['ano']).map { |ano| preco_de(get(base(params, "#{do_veiculo}/years/#{ano['codigo']}"))) } }
  end

  def do_ano(anos, ano)
    escolhidos = anos.select { |item| item['codigo'].to_s.split('-').first.to_i == ano }.first(Fipe::MAX_ANOS_COM_PRECO)
    raise NaoEncontrado if escolhidos.empty?

    escolhidos
  end

  def preco_de(item)
    raise Falha, 'resposta_invalida' unless item.is_a?(Hash) && item['price'].present?

    Fipe.preco(valor: item['price'], marca: item['brand'], modelo: item['model'], ano_modelo: item['modelYear'],
               combustivel: item['fuel'], codigo_fipe: item['codeFipe'], mes_de_referencia: item['referenceMonth'])
  end
end

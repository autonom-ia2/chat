# A FIPE na parallelum (reserva; e a única com a lista de modelos e o preço por marca e modelo).
class Autonomia::FerramentasProntas::Fontes::Fipe::Parallelum < Autonomia::FerramentasProntas::Provedor
  Fipe = Autonomia::FerramentasProntas::Fontes::Fipe

  NOME = 'parallelum'.freeze
  HOST = 'parallelum.com.br'.freeze
  TIPO_NA_FONTE = { 'carros' => 'cars', 'motos' => 'motorcycles', 'caminhoes' => 'trucks' }.freeze
  # A chave gratuita (1.000 pedidos por dia em vez de 500), opcional: sem ela, a fonte funciona igual. Só o nome da
  # variável fica no código. O teto global acompanha (`TetoDoProvedor.tetos`).
  CHAVE = 'AUTONOMIA_PRONTAS_FIPE_TOKEN'.freeze
  # Os motivos do cliente HTTP que querem dizer "acabou o tempo": a chamada ou a consulta inteira.
  SEM_TEMPO = %w[tempo_esgotado prazo_total].freeze

  def self.chave
    chave_do_ambiente(CHAVE)
  end

  def self.cabecalhos
    chave ? { 'X-Subscription-Token' => chave } : {}
  end

  # A lista parcial dos modelos do ano (o prazo acabou no meio dos códigos) não vai ao cache: a próxima consulta lê todos.
  # `parcial` guarda o motivo do corte ("parallelum.prazo_total"), que `PeloNome` repassa quando nada serve.
  def self.validade_da_resposta(dados)
    dados['parcial'] ? 0 : validade
  end

  def consultar(consulta, params)
    case consulta.nome
    when 'marcas' then Fipe.lista(exigir!(itens(base(params, '/brands'))), 'marcas', Fipe::MAX_MARCAS)
    when 'modelos' then modelos(params)
    when 'modelos_do_ano' then modelos_do_ano(params)
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

  # Os modelos da marca que têm o ano-modelo: os códigos de ano da marca (um por combustível, "2020-1", "2020-5") e os
  # modelos de TODOS eles (revisão do #2906: só os 3 primeiros deixavam de fora a versão de outro combustível). A lista
  # fica no cache da consulta (`MODELOS_DO_ANO`), e o preço de outra versão do mesmo ano não lê os códigos de novo.
  # O prazo que acaba depois de ao menos um código lido: o que veio serve, com `parcial` = o motivo do corte (sem cache;
  # e `PeloNome` não diz que o ano não existe por ela, nem que uma versão lida é a única).
  def modelos_do_ano(params)
    lidos = []
    codigos_do_ano(params).each do |ano|
      lidos.concat(itens(base(params, "/brands/#{params['marca']}/years/#{ano['codigo']}/models")))
    end
    { 'modelos' => lidos.uniq { |item| item['codigo'] } }
  rescue Falha => e
    raise unless lidos.any? && SEM_TEMPO.include?(e.motivo)

    { 'modelos' => lidos.uniq { |item| item['codigo'] }, 'parcial' => "#{NOME}.#{e.motivo}" }
  end

  # Os códigos de ano da marca naquele ano-modelo, um por combustível ("2020-1", "2020-5").
  def codigos_do_ano(params)
    anos = itens(base(params, "/brands/#{params['marca']}/years"))
    anos.select { |item| codigo_de_ano?(item['codigo']) && item['codigo'].split('-').first.to_i == params['ano'] }
  end

  # Sem o ano, os anos que existem e a faixa; com ele, o preço de cada combustível daquele ano (até `MAX_ANOS_COM_PRECO`).
  # Várias versões do ano (`PeloNome`, o modelo vem com os `exemplos`): o preço de cada um, do mais barato ao mais caro.
  def precos(params)
    return versoes(params) if params['modelo'].is_a?(Hash)

    do_veiculo = params['codigo_fipe'] ? "/#{params['codigo_fipe']}" : "/brands/#{params['marca']}/models/#{params['modelo']}"
    anos = anos_do_veiculo(params, do_veiculo)
    raise NaoEncontrado if anos.empty?
    return faixa(params, do_veiculo, anos) if params['ano'].nil?

    escolhidos = do_ano(anos, params['ano'])
    return sem_o_ano(anos, params['ano']) if escolhidos.empty?

    { 'precos' => escolhidos.map { |ano| preco_do_ano(params, do_veiculo, ano) } }
  end

  # `params['modelo']`: as versões de exemplo (até `MAX_VERSOES`) e se há outras no ano (`PeloNome#do_ano`).
  def versoes(params)
    precos = params['modelo']['exemplos'].first(Fipe::MAX_VERSOES).filter_map do |modelo|
      um = params.merge('modelo' => modelo)
      do_veiculo = "/brands/#{params['marca']}/models/#{modelo}"
      ano = do_ano(anos_do_veiculo(um, do_veiculo), params['ano']).first
      preco_do_ano(um, do_veiculo, ano) if ano
    end
    raise NaoEncontrado if precos.empty?

    ordenados = { 'precos' => precos.sort_by { |preco| preco['valor'].to_f } }
    ordenados.merge('observacao' => observacao_das_versoes(params['modelo']['ha_outras'], precos.size))
  end

  # Sempre há mais de uma versão aqui (ou a lista parcial, que pode ter outras): um preço só é o de uma delas; dois, das 2,
  # e "há outras" quando há.
  def observacao_das_versoes(ha_outras, precos)
    return Fipe::UMA_DAS_VERSOES if precos == 1

    ha_outras ? Fipe::VERSOES_E_OUTRAS : Fipe::VERSOES
  end

  # O ano que o veículo não tem: os anos que ele tem, para o agente dizer ao cliente (varredura F13).
  def sem_o_ano(anos, ano)
    { 'anos_disponiveis' => anos.pluck('nome'), 'observacao' => format(Fipe::SEM_O_ANO, ano: ano) }
  end

  # Os anos de um veículo mudam uma vez por mês: ficam no cache da fonte por 7 dias (`Fipe::ANOS`), e o preço de outro
  # ano do mesmo carro gasta só a chamada do preço.
  def anos_do_veiculo(params, do_veiculo)
    cache = Autonomia::FerramentasProntas::Cache.new(Fipe::FONTE, Fipe::ANOS, params)
    guardado = cache.ler
    return guardado['dados'] if guardado && guardado['situacao'] == Autonomia::FerramentasProntas::Cache::ENCONTRADO

    itens(base(params, "#{do_veiculo}/years")).tap { |anos| cache.encontrado(anos) if anos.any? }
  end

  # O preço do ano mais antigo e do mais novo da lista de anos (do cache), o zero km (32000) sendo o mais novo: duas
  # chamadas, não uma por ano. Se elas falharem, os anos ainda servem ao agente.
  def faixa(params, do_veiculo, anos)
    so_os_anos = { 'anos_disponiveis' => anos.pluck('nome') }
    validos = anos.select { |item| codigo_de_ano?(item['codigo']) }
    return so_os_anos if validos.empty?

    extremos = validos.minmax_by { |item| item['codigo'].split('-').first.to_i }.uniq
    { 'precos' => extremos.map { |ano| preco_do_ano(params, do_veiculo, ano) } }.merge(so_os_anos, 'observacao' => Fipe::FAIXA)
  rescue Falha
    so_os_anos
  end

  def preco_do_ano(params, do_veiculo, ano)
    preco_de(get(base(params, "#{do_veiculo}/years/#{ano['codigo']}")))
  end

  # O código do ano vem da própria fonte e volta ao caminho: só no formato "2020-5" (dígitos, hífen, dígitos).
  def do_ano(anos, ano)
    validos = anos.select { |item| codigo_de_ano?(item['codigo']) }
    validos.select { |item| item['codigo'].split('-').first.to_i == ano }.first(Fipe::MAX_ANOS_COM_PRECO)
  end

  def codigo_de_ano?(codigo)
    partes = codigo.to_s.split('-')
    partes.size == 2 && partes.all? { |parte| Autonomia::FerramentasProntas::Parametro.codigo(parte) }
  end

  # O preço sem valor que se leia (`Fipe.valor` devolve nil) não serve: falha (revisão do #2906).
  def preco_de(item)
    raise Falha, 'resposta_invalida' unless item.is_a?(Hash) && item['price'].present?

    preco = Fipe.preco(valor: item['price'], marca: item['brand'], modelo: item['model'], ano_modelo: item['modelYear'],
                       combustivel: item['fuel'], codigo_fipe: item['codeFipe'], mes_de_referencia: item['referenceMonth'])
    exigir!(preco['valor'])
    preco
  end
end

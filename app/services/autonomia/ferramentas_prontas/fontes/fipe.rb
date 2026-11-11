# VALOR DO CARRO PELA TABELA FIPE (#2858): BrasilAPI, com a parallelum de reserva (`fipe/*.rb`). Uma fonte, três
# consultas; o agente escolhe a consulta pelo sentido da conversa. Regra "QI 70": o preço aceita a marca e o modelo pelo
# NOME, como o cliente disse, e a plataforma tira o código das listas (`fipe/pelo_nome.rb`); a cadeia marcas -> modelos
# -> preço fica com o servidor, não com o modelo.
#   - marcas: BrasilAPI, reserva parallelum;
#   - modelos: só a parallelum tem a lista de modelos de uma marca;
#   - preço: pelo código FIPE (BrasilAPI, reserva parallelum) ou por marca e modelo (parallelum). Sem o ano, a
#     parallelum devolve os anos que existem e a faixa (o preço do ano mais antigo e do mais novo), para o agente mostrar
#     a faixa antes de perguntar o ano.
# Termos: as duas são gratuitas; a parallelum sem chave aceita poucas centenas de pedidos por dia por IP, por isso ela
# é só reserva e o cache segura o resto. A tabela muda uma vez por mês: preço com 1 dia de cache, listas com 7.
module Autonomia::FerramentasProntas::Fontes::Fipe
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  TIPOS = %w[carros motos caminhoes].freeze
  MAX_MARCAS = 200
  MAX_MODELOS = 40
  MAX_PRECOS = 12
  # Os anos de um modelo que viram preço numa chamada só da reserva (cada um é um pedido a mais à parallelum).
  MAX_ANOS_COM_PRECO = 3
  # Na FIPE, 32000 é o "zero km".
  ZERO_KM = 32_000
  FAIXA = 'Sem o ano: o preço do ano mais antigo e do mais novo (a faixa). Mostre a faixa ao cliente e só então pergunte ' \
          'o ano-modelo.'.freeze

  def self.lista(itens, chave, maximo)
    Autonomia::FerramentasProntas::Lista.cortar(itens, chave, maximo)
  end

  # A busca pelo nome do modelo, sobre a lista inteira da marca (da fonte ou do cache). Sem busca, a lista com o teto.
  # -> nil quando nada sobrou.
  def self.refinar_modelos(dados, params)
    achados = Autonomia::FerramentasProntas::Lista.filtrar(Array(dados['modelos']), params['busca']) { |item| item['nome'] }
    lista(achados, 'modelos', MAX_MODELOS) if achados.any?
  end

  # `campos`: valor, marca, modelo, ano_modelo, combustivel, codigo_fipe, mes_de_referencia. O vazio sai.
  def self.preco(campos)
    campos.transform_keys(&:to_s).transform_values { |valor| valor.is_a?(String) ? valor.strip.presence : valor }.compact
  end

  # O preço pede o código FIPE, ou a marca e o modelo. Falta: a marca ou o modelo (o código é dado técnico: o agente
  # nunca o pede ao cliente).
  def self.regra_do_preco(params)
    return if params['codigo_fipe']
    return 'marca' unless params['marca']

    'modelo' unless params['modelo']
  end

  # O código (como veio de uma lista) ou o nome que o cliente disse.
  def self.codigo_ou_nome(valor)
    Parametro.codigo(valor) || Parametro.texto_curto(valor)
  end

  TIPO = Parametro.new(nome: 'tipo', descricao: 'O tipo de veículo.', opcoes: TIPOS,
                       deduza: 'escolha carros, motos ou caminhoes pelo veículo de que o cliente falou.')
  MARCA = Parametro.new(nome: 'marca', descricao: 'O nome da marca como o cliente disse (ex.: Volkswagen), ou o código dela.',
                        deduza: 'mande o nome da marca; se o cliente disse só o modelo, a marca sai dele (Gol é Volkswagen).') do |valor|
    codigo_ou_nome(valor)
  end
  MODELO = Parametro.new(nome: 'modelo', descricao: 'O nome do modelo como o cliente disse (ex.: Gol, Onix LT), ou o código dele.',
                         pergunte: 'o modelo do veículo') { |valor| codigo_ou_nome(valor) }
  BUSCA = Parametro.new(nome: 'busca', local: true,
                        descricao: 'Parte do nome do modelo para filtrar a lista (ex.: "onix lt 1.0"). Opcional.') do |valor|
    Parametro.texto_curto(valor)
  end
  CODIGO_FIPE = Parametro.new(nome: 'codigo_fipe', descricao: 'O código FIPE do veículo (ex.: 004517-9), se o cliente informou.',
                              deduza: 'deixe o código FIPE vazio e mande marca e modelo.') do |valor|
    digitos = Parametro.digitos(valor, 7)
    "#{digitos[0, 6]}-#{digitos[6]}" if digitos
  end
  ANO = Parametro.new(nome: 'ano', tipo: 'integer', descricao: 'O ano-modelo (ex.: 2020; 32000 é zero km).',
                      pergunte: 'o ano-modelo do veículo') do |valor|
    Parametro.inteiro(valor, 1950..2100) || Parametro.inteiro(valor, ZERO_KM..ZERO_KM)
  end

  PRECO = 'o preço do mês; pede tipo, marca e modelo pelo nome, como o cliente disse (o código sai das listas aqui), e o ' \
          'ano; ou o código FIPE. Sem o ano, vem a faixa e os anos que existem'.freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'fipe', slug: 'pronta_fipe', nome: 'Valor do carro (FIPE)',
    descricao: 'Consulta oficial e gratuita da tabela FIPE do mês: marcas, modelos de uma marca e o preço de um ' \
               'veículo por ano-modelo.',
    consultas: [
      Consulta.new(nome: 'marcas', descricao: 'as marcas e os códigos delas; pede tipo', obrigatorios: [TIPO],
                   provedores: [BrasilApi, Parallelum], validade: 7.days, prazo_por_fonte: 4, prazo_total: 8),
      Consulta.new(nome: 'modelos', descricao: 'os modelos de uma marca; pede tipo e marca, e aceita busca pelo nome',
                   obrigatorios: [TIPO, MARCA], opcionais: [BUSCA], provedores: [Parallelum], validade: 7.days,
                   prazo_por_fonte: 5, prazo_total: 9, refinar: method(:refinar_modelos), resolver: PeloNome.method(:resolver)),
      Consulta.new(nome: 'preco', descricao: PRECO, obrigatorios: [TIPO], opcionais: [CODIGO_FIPE, MARCA, MODELO, ANO],
                   provedores: [BrasilApi, Parallelum], validade: 1.day, prazo_por_fonte: 4, prazo_total: 12,
                   regra: method(:regra_do_preco), resolver: PeloNome.method(:resolver))
    ],
    limite_diario: 500,
    termos: 'BrasilAPI e parallelum: gratuitas; a parallelum sem chave tem teto diário por IP e fica só de reserva. ' \
            'Cache de 1 dia no preço e 7 dias nas listas.'
  )
end

# VALOR DO CARRO PELA TABELA FIPE (#2858): BrasilAPI, com a parallelum de reserva (`fipe/*.rb`). Uma fonte, três
# consultas; o agente escolhe a consulta pelo sentido da conversa e encadeia: marcas -> modelos (com a busca pelo nome)
# -> preço.
#   - marcas: BrasilAPI, reserva parallelum;
#   - modelos: só a parallelum tem a lista de modelos de uma marca;
#   - preço: pelo código FIPE (BrasilAPI, reserva parallelum) ou por marca e modelo (parallelum). Sem o ano, a
#     parallelum devolve os anos que existem, para o agente perguntar ou escolher.
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

  def self.lista(itens, chave, maximo)
    { chave => itens.first(maximo), 'total' => itens.size }.merge(itens.size > maximo ? { 'mostrando' => maximo } : {})
  end

  # A busca pelo nome do modelo, sobre a lista inteira da marca (da fonte ou do cache): todas as palavras no nome.
  # Sem busca, a lista com o teto. -> nil quando nada sobrou.
  def self.refinar_modelos(dados, params)
    palavras = params['busca'].to_s.downcase.split
    achados = Array(dados['modelos']).select { |item| palavras.all? { |palavra| item['nome'].to_s.downcase.include?(palavra) } }
    lista(achados, 'modelos', MAX_MODELOS) if achados.any?
  end

  # `campos`: valor, marca, modelo, ano_modelo, combustivel, codigo_fipe, mes_de_referencia. O vazio sai.
  def self.preco(campos)
    campos.transform_keys(&:to_s).transform_values { |valor| valor.is_a?(String) ? valor.strip.presence : valor }.compact
  end

  TIPO = Parametro.new(nome: 'tipo', descricao: 'O tipo de veículo.', opcoes: TIPOS)
  MARCA = Parametro.new(nome: 'marca', descricao: 'O código da marca, como veio na consulta marcas.') { |valor| Parametro.codigo(valor) }
  MODELO = Parametro.new(nome: 'modelo', descricao: 'O código do modelo, como veio na consulta modelos.') { |valor| Parametro.codigo(valor) }
  BUSCA = Parametro.new(nome: 'busca', local: true,
                        descricao: 'Parte do nome do modelo para filtrar a lista (ex.: "onix lt 1.0"). Opcional.') do |valor|
    Parametro.texto_curto(valor)
  end
  CODIGO_FIPE = Parametro.new(nome: 'codigo_fipe', descricao: 'O código FIPE do veículo (ex.: 004517-9), se o cliente informou.') do |valor|
    digitos = Parametro.digitos(valor, 7)
    "#{digitos[0, 6]}-#{digitos[6]}" if digitos
  end
  ANO = Parametro.new(nome: 'ano', tipo: 'integer', descricao: 'O ano-modelo (ex.: 2020; 32000 é zero km).') do |valor|
    Parametro.inteiro(valor, 1950..2100) || Parametro.inteiro(valor, ZERO_KM..ZERO_KM)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'fipe', slug: 'pronta_fipe', nome: 'Valor do carro (FIPE)',
    descricao: 'Consulta oficial e gratuita da tabela FIPE do mês: marcas, modelos de uma marca e o preço de um ' \
               'veículo por ano-modelo.',
    consultas: [
      Consulta.new(nome: 'marcas', descricao: 'as marcas e os códigos delas; pede tipo', obrigatorios: [TIPO],
                   provedores: [BrasilApi, Parallelum], validade: 7.days, prazo_por_fonte: 4, prazo_total: 8),
      Consulta.new(nome: 'modelos', descricao: 'os modelos de uma marca; pede tipo e marca, e aceita busca pelo nome',
                   obrigatorios: [TIPO, MARCA], opcionais: [BUSCA], provedores: [Parallelum], validade: 7.days,
                   prazo_por_fonte: 5, prazo_total: 5, refinar: method(:refinar_modelos)),
      Consulta.new(nome: 'preco', descricao: 'o preço do mês; pede tipo e o código FIPE, ou marca e modelo, e o ano',
                   obrigatorios: [TIPO], opcionais: [CODIGO_FIPE, MARCA, MODELO, ANO],
                   provedores: [BrasilApi, Parallelum], validade: 1.day, prazo_por_fonte: 4, prazo_total: 9,
                   regra: ->(params) { 'codigo_fipe' unless params['codigo_fipe'] || (params['marca'] && params['modelo']) })
    ],
    limite_diario: 300,
    termos: 'BrasilAPI e parallelum: gratuitas; a parallelum sem chave tem teto diário por IP e fica só de reserva. ' \
            'Cache de 1 dia no preço e 7 dias nas listas.'
  )
end

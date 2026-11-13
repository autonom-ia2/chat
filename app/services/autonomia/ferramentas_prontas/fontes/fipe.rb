# VALOR DO CARRO PELA TABELA FIPE (#2858): BrasilAPI, com a parallelum de reserva (`fipe/*.rb`). Uma fonte, três
# consultas; o agente escolhe a consulta pelo sentido da conversa. Regra "QI 70": o preço aceita a marca e o modelo pelo
# NOME, como o cliente disse, e a plataforma tira o código das listas (`fipe/pelo_nome.rb`); a cadeia marcas -> modelos
# -> preço fica com o servidor, não com o modelo.
#   - marcas: BrasilAPI, reserva parallelum;
#   - modelos: só a parallelum tem a lista de modelos de uma marca;
#   - preço: pelo código FIPE (BrasilAPI, reserva parallelum) ou por marca e modelo (parallelum). Sem o ano, a
#     parallelum devolve os anos que existem e a faixa (o preço do ano mais antigo e do mais novo), para o agente mostrar
#     a faixa antes de perguntar o ano.
#   - veículo (#2993): pela placa ou pelo chassi, numa fonte parceira, com o cadastro da plataforma
#     (`fipe/pela_placa.rb`): a placa, o chassi, a marca, o modelo, os anos e as versões, as 2 primeiras com o valor do
#     mês (que sai da consulta preço, pelo código). Sem o cadastro no ambiente, a consulta não é oferecida e o card segue com as outras três.
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
  # Várias versões do modelo no ano (o Gol 2020): o preço de duas delas, sem exigir a escolha (varredura F12). De
  # propósito (decisão do Rodrigo, #2906): duas versões de exemplo, a de nome mais curto e a de nome mais longo, não o
  # mínimo e o máximo da tabela; o texto não as apresenta como "entre X e Y".
  MAX_VERSOES = 2
  # Os textos que vão nos dados cabem em `Resposta::MAX_TEXTO` (160): o resto seria cortado.
  VERSOES = 'Preço das 2 versões desse modelo no ano: o exato depende da versão. Se o cliente quiser o exato, pergunte a ' \
            'versão.'.freeze
  # Várias versões no ano e só um preço respondeu (a outra versão não tem preço naquele ano): o preço é de uma delas.
  UMA_DAS_VERSOES = 'Preço de uma das versões desse modelo no ano, como exemplo (há outras): o exato depende da versão. ' \
                    'Se o cliente quiser o exato, pergunte a versão.'.freeze
  # Mais de 2 versões no ano: "há outras" só aqui.
  VERSOES_E_OUTRAS = 'Preço de 2 versões desse modelo no ano, como exemplo (há outras): não é o mínimo nem o máximo da ' \
                     'tabela. Para o exato, pergunte a versão.'.freeze
  SEM_O_ANO = 'Não há o ano-modelo %<ano>s deste veículo na tabela FIPE. Os anos que existem vêm na resposta: diga isso ao ' \
              'cliente e confirme o ano.'.freeze
  # O preço vai em número e o mês em AAAA-MM (varredura P09): quem formata é a tela, no idioma dela, e o agente lê o
  # número igual. A moeda vai em `unidades`.
  UNIDADES = { 'valor' => 'R$' }.freeze
  MESES = %w[janeiro fevereiro março abril maio junho julho agosto setembro outubro novembro dezembro].freeze
  TAMANHO_DO_ANO = 4
  TAMANHO_DO_CHASSI = 17
  # As letras que o chassi (o VIN) nunca tem, por se confundirem com 1 e 0.
  FORA_DO_CHASSI = 'IOQ'.freeze

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
    limpos = campos.transform_keys(&:to_s).transform_values { |valor| valor.is_a?(String) ? valor.strip.presence : valor }.compact
    limpos.merge('valor' => valor(limpos['valor']), 'mes_de_referencia' => mes(limpos['mes_de_referencia'])).compact
  end

  # "R$ 56.043,00" (o formato das duas fontes) -> 56043.0. Fora dele, nil: o preço sem valor não serve.
  def self.valor(texto)
    return texto.to_f if texto.is_a?(Numeric)

    Float(texto.to_s.delete('^0-9,').tr(',', '.'), exception: false)
  end

  # "novembro de 2026" (o formato das duas fontes, não texto de pessoa) -> "2026-11". Fora dele, como veio.
  def self.mes(texto)
    return if texto.nil?

    partes = Autonomia::FerramentasProntas::Lista.comparavel(texto).split
    numero = MESES.index { |nome| Autonomia::FerramentasProntas::Lista.comparavel(nome) == partes.first }
    ano = partes.last.to_s
    return texto unless numero && ano.length == TAMANHO_DO_ANO && ano.delete(Parametro::DIGITOS).empty?

    format('%<ano>s-%<mes>02d', ano: ano, mes: numero + 1)
  end

  def self.refinar_preco(dados, _params)
    dados['precos'] ? dados.merge('unidades' => UNIDADES) : dados
  end

  # O preço pede o código FIPE, ou a marca e o modelo. Falta: a marca ou o modelo (o código é dado técnico: o agente
  # nunca o pede ao cliente).
  def self.regra_do_preco(params)
    return if params['codigo_fipe']
    return 'marca' unless params['marca']

    'modelo' unless params['modelo']
  end

  # O veículo pede a placa ou o chassi. Falta: a placa (é o que o cliente tem em mãos).
  def self.regra_do_veiculo(params)
    'placa' unless params['placa'] || params['chassi']
  end

  # "9bw zzz377 vt004251" -> "9BWZZZ377VT004251": 17 letras ou dígitos, sem I, O e Q.
  def self.chassi(valor)
    texto = valor.to_s.upcase.delete("^#{Parametro::ALFANUMERICO}")
    texto if texto.length == TAMANHO_DO_CHASSI && texto.count(FORA_DO_CHASSI).zero?
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
  MODELO = Parametro.new(nome: 'modelo', descricao: 'O nome do modelo como o cliente disse (ex.: Gol, 208), ou o código como veio ' \
                                                    'na consulta modelos.',
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
  # Qualquer ano de 4 dígitos passa: se ele existe para o veículo, quem diz é a tabela (varredura F13, "Gol 1850").
  ANO = Parametro.new(nome: 'ano', tipo: 'integer', descricao: 'O ano-modelo (ex.: 2020; 32000 é zero km).',
                      pergunte: 'o ano-modelo do veículo') do |valor|
    Parametro.inteiro(valor, 1000..2100) || Parametro.inteiro(valor, ZERO_KM..ZERO_KM)
  end

  # A mesma regra de placa do card Premium (antiga ou Mercosul, com ou sem traço).
  PLACA = Parametro.new(nome: 'placa', descricao: 'A placa do veículo como o cliente escreveu (antiga ou Mercosul, com ou sem traço).',
                        pergunte: 'a placa do veículo (ou o chassi, se ele não tiver a placa)') do |valor|
    Autonomia::FerramentasProntas::Premium::Parametros.placa(valor)
  end
  CHASSI = Parametro.new(nome: 'chassi', descricao: 'O chassi do veículo (17 letras e números), se o cliente informou em vez da placa.',
                         pergunte: 'o chassi do veículo, com as 17 letras e números, ou a placa') { |valor| chassi(valor) }

  # Interna, fora da lista que o modelo vê: os anos de um veículo, guardados no cache da fonte pela parallelum.
  ANOS = Consulta.new(nome: 'anos', descricao: 'os anos de um veículo (interna)', obrigatorios: [TIPO],
                      opcionais: [CODIGO_FIPE, MARCA, MODELO], provedores: [], validade: 7.days, prazo_por_fonte: 5, prazo_total: 5)
  # Interna: os modelos de uma marca que têm o ano-modelo (`PeloNome`, para estreitar as versões pelo ano).
  MODELOS_DO_ANO = Consulta.new(nome: 'modelos_do_ano', descricao: 'os modelos de uma marca num ano (interna)',
                                obrigatorios: [TIPO, MARCA, ANO], provedores: [Parallelum], validade: 7.days,
                                prazo_por_fonte: 5, prazo_total: 5)

  PRECO = 'o preço do mês; pede tipo, marca e modelo pelo nome, como o cliente disse (o código sai das listas aqui), e o ' \
          'ano; ou o código FIPE. Sem o ano, vem a faixa e os anos que existem'.freeze
  VEICULO = 'o veículo pela placa (ou pelo chassi): placa, chassi, marca, modelo, ano, versões e o valor do mês. Com a ' \
            'placa em mãos, use esta em vez de perguntar marca, modelo e ano'.freeze
  VEICULO_NAO_ENCONTRADO = 'Não achei veículo com essa placa ou esse chassi. Confira o dado com o cliente; se estiver ' \
                           'certo, siga pedindo a marca, o modelo e o ano. Não invente.'.freeze

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
                   regra: method(:regra_do_preco), resolver: PeloNome.method(:resolver), refinar: method(:refinar_preco)),
      # No turno: cabe na janela de 8 s (`Consulta::FOLGA_DO_TURNO`). A fonte respondeu em menos de 0,1 s por chamada
      # (medido em 13/11/2026); o resto do prazo é da FIPE.
      Consulta.new(nome: 'veiculo', descricao: VEICULO, opcionais: [PLACA, CHASSI], provedores: [PelaPlaca], validade: 1.day,
                   prazo_por_fonte: 3, prazo_total: 7, regra: method(:regra_do_veiculo), nao_encontrado: VEICULO_NAO_ENCONTRADO)
    ],
    limite_diario: 500,
    termos: 'BrasilAPI e parallelum: gratuitas; a parallelum sem chave tem teto diário por IP e fica só de reserva. ' \
            'Cache de 1 dia no preço e 7 dias nas listas. Veículo pela placa: fonte parceira, com o cadastro da ' \
            'plataforma; cache de 1 dia.'
  )
end

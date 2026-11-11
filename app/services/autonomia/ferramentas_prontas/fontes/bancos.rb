# BANCOS (#2858, F1): o nome do banco pelo código de compensação (o "341" do boleto e da transferência), e o código
# pelo nome (regra "QI 70" do Rodrigo, 11/11/2026: o cliente diz "Itaú", não "341").
#   - banco: BrasilAPI; reserva: a lista oficial de participantes do STR do Banco Central (CSV público);
#   - por_nome: a lista inteira (BrasilAPI, reserva o mesmo CSV do STR) vai ao cache uma vez, e o nome é procurado aqui
#     (`Lista.pelo_nome`, sem acento e pelo começo de palavra), no nome curto e no completo. O nome comercial que não é
#     o de registro (Nubank é "Nu Pagamentos") não é adivinhado por lista de apelidos: a descrição e o "não encontrado"
#     dizem ao modelo para tentar o nome de registro, que ele sabe.
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real"; o CSV do Banco Central é dado aberto. Cache de 30 dias.
module Autonomia::FerramentasProntas::Fontes::Bancos
  Parametro = Autonomia::FerramentasProntas::Parametro
  Lista = Autonomia::FerramentasProntas::Lista

  MAX_BANCOS = 10
  MIN_NOME = 2
  NAO_ENCONTRADO = 'Nenhum banco com esse nome no cadastro do Banco Central. O nome de registro pode ser outro que o ' \
                   'comercial (Nubank é Nu Pagamentos, PagBank é PagSeguro): tente o nome de registro antes de perguntar ' \
                   'ao cliente. Não invente o código.'.freeze

  module_function

  def banco(codigo:, nome:, nome_completo:, ispb:)
    { 'codigo' => codigo, 'nome' => nome, 'nome_completo' => nome_completo, 'ispb' => ispb }.compact
  end

  # 341, "1", "001" -> "341", "001", "001"; nil fora de 1 a 3 dígitos.
  def codigo(valor)
    texto = valor.to_s.strip
    texto.rjust(3, '0') if texto.present? && texto.length <= 3 && texto.delete(Parametro::DIGITOS).empty?
  end

  # Os bancos com esse nome (no curto ou no completo), o mais parecido primeiro. -> nil quando nenhum.
  def refinar_por_nome(dados, params)
    itens = Array(dados['bancos'])
    achados = (Lista.pelo_nome(itens, params['nome']) { |item| item['nome'] } +
               Lista.pelo_nome(itens, params['nome']) { |item| item['nome_completo'].to_s }).uniq
    return if achados.empty?

    Lista.cortar(Lista.em_ordem(achados, params['nome']) { |item| item['nome'] }, 'bancos', MAX_BANCOS)
  end

  CODIGO = Parametro.new(nome: 'codigo', descricao: 'Na consulta banco: o código do banco, de 1 a 3 dígitos (ex.: 341).',
                         deduza: 'se o cliente disse o nome do banco, use a consulta por_nome; o código tem de 1 a 3 dígitos.') do |valor|
    codigo(valor)
  end
  NOME = Parametro.new(nome: 'nome', local: true, descricao: 'Na consulta por_nome: o nome do banco como o cliente disse (ex.: Itaú).',
                       pergunte: 'o nome do banco') do |valor|
    texto = Parametro.texto_curto(valor)
    texto if texto && texto.length >= MIN_NOME
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'bancos', slug: 'pronta_bancos', nome: 'Bancos', flag: Autonomia::FerramentasProntas::FLAG_CONSULTAS,
    consulta_padrao: 'banco',
    descricao: 'O nome do banco pelo código de compensação (ex.: 341), ou o código pelo nome do banco.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'banco', descricao: 'o banco do código; pede codigo', obrigatorios: [CODIGO], provedores: [BrasilApi, Str],
        validade: 30.days, prazo_por_fonte: 3, prazo_total: 6
      ),
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'por_nome', descricao: 'o código do banco pelo nome (o de registro, se o comercial for outro); pede nome',
        obrigatorios: [NOME], provedores: [BrasilApi, Str], validade: 30.days, prazo_por_fonte: 4, prazo_total: 8,
        refinar: method(:refinar_por_nome), nao_encontrado: NAO_ENCONTRADO
      )
    ],
    limite_diario: 500,
    termos: 'BrasilAPI (uso de pessoa real) e a lista do STR do Banco Central (dado aberto) de reserva. Cache de 30 dias.'
  )
end

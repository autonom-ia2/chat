# HOSPITAIS E CLÍNICAS (#2858, F4): os estabelecimentos de saúde de uma cidade, do CNES (Cadastro Nacional de
# Estabelecimentos de Saúde, Ministério da Saúde), com filtro opcional pelo tipo de unidade e pelo nome.
#   - a cidade vem pelo código IBGE (7 dígitos, ou os 6 que o CNES usa) ou pelo nome (a UF sai dele; só a homônima a
#     pede), conferidos na tabela das sedes municipais (`Municipios`): a cidade que não existe é pedido inválido, e nada
#     é consultado;
#   - fonte única: a API de dados abertos do Ministério da Saúde (`hospitais/cnes.rb`). Não há outra API aberta e
#     documentada do CNES para servir de reserva;
#   - a API devolve no máximo 20 por pedido: o tipo vai à fonte, e a busca pelo nome filtra esses 20 aqui;
#   - nenhum dado de pessoa física: o estabelecimento registrado em nome de pessoa (natureza jurídica do grupo 4, o
#     consultório de um profissional) sai da resposta, e e-mail, CNPJ e razão social não vão ao modelo.
# Termos: dado aberto do Ministério da Saúde, sem chave e sem limite publicado. O cadastro muda todo mês: cache de 7 dias.
module Autonomia::FerramentasProntas::Fontes::Hospitais
  Parametro = Autonomia::FerramentasProntas::Parametro
  Municipios = Autonomia::FerramentasProntas::Municipios

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MAX_ESTABELECIMENTOS = 20
  POR_PAGINA = 20
  MAX_PAGINAS = 5
  # Cabe em `Resposta::MAX_TEXTO` (160).
  AMOSTRA = 'É uma amostra: os %<lidos>d primeiros cadastros da cidade, e o total é só deles. Para achar pelo nome, mande ' \
            'a busca e, se souber, o tipo (santa casa é hospital).'.freeze
  # O tipo de unidade que o modelo escolhe -> o código do CNES (`/cnes/tipounidades`).
  TIPOS = {
    'hospital' => 5, 'hospital_especializado' => 7, 'hospital_dia' => 62, 'pronto_socorro' => 20,
    'pronto_socorro_especializado' => 21, 'pronto_atendimento' => 73, 'unidade_basica' => 2, 'posto_de_saude' => 1,
    'policlinica' => 4, 'clinica' => 36, 'consultorio' => 22, 'exames_e_diagnostico' => 39, 'farmacia' => 43,
    'caps' => 70, 'centro_de_parto' => 61, 'vacinacao' => 85
  }.freeze

  # O CNES não busca pelo nome: o nome é procurado nas páginas lidas, e a cidade grande só é lida em parte (varredura
  # F22: a "santa casa" de Campinas, sem o tipo, ficou fora das 100 primeiras).
  NAO_ENCONTRADO = 'Nada com esse nome entre os cadastros lidos da cidade. Mande de novo com o tipo do lugar (santa casa ' \
                   'é hospital), que estreita a lista; se ainda não achar, diga isso ao cliente. Não invente.'.freeze

  module_function

  # Cidade obrigatória: o código IBGE, ou o nome (com a UF só quando o nome existe em mais de um estado).
  def regra(params)
    return if params['codigo_ibge']

    Municipios.falta(params['uf'], params['cidade'])
  end

  # O filtro pelo nome roda sobre todas as páginas lidas. Lista que não veio inteira (`amostra`): a observação diz que o
  # total é só do que foi lido (varredura F21).
  def refinar(dados, params)
    todos = Array(dados['estabelecimentos'])
    achados = Autonomia::FerramentasProntas::Lista.filtrar(todos, params['busca']) { |item| item['nome'] }
    return if achados.empty?

    resposta = dados.except('estabelecimentos', 'amostra', 'pagina_falhou')
                    .merge(Autonomia::FerramentasProntas::Lista.cortar(achados, 'estabelecimentos', MAX_ESTABELECIMENTOS))
    dados['amostra'] ? resposta.merge('observacao' => format(AMOSTRA, lidos: todos.size)) : resposta
  end

  CODIGO_IBGE = Parametro.new(nome: 'codigo_ibge', descricao: 'O código IBGE da cidade (7 dígitos), se já souber. Opcional.',
                              deduza: 'deixe o código vazio e mande o nome da cidade.') do |valor|
    digitos = valor.to_s.delete("^#{Parametro::DIGITOS}")
    codigo = digitos.length == 7 ? digitos[0, 6] : digitos
    codigo if codigo.length == Municipios::DIGITOS_CNES && Municipios.por_codigo_cnes(codigo)
  end
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade (ex.: Campinas).', pergunte: 'a cidade') do |valor|
    Parametro.texto_curto(valor)
  end
  UF = Municipios.parametro_uf
  TIPO = Parametro.new(nome: 'tipo', descricao: 'O tipo de unidade, se o cliente pediu um. Opcional.', opcoes: TIPOS.keys,
                       deduza: 'escolha da lista o tipo que o cliente pediu, ou deixe vazio.')
  BUSCA = Parametro.new(nome: 'busca', local: true,
                        descricao: 'Parte do nome do estabelecimento. Opcional. Com ela, mande também o tipo quando souber (santa ' \
                                   'casa é hospital): cidade grande tem milhares de cadastros, e só os primeiros são lidos.') do |valor|
    Parametro.texto_curto(valor)
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'hospitais', slug: 'pronta_hospitais', nome: 'Hospitais e clínicas', flag: FLAG,
    descricao: 'Hospitais, clínicas, prontos-socorros e outros estabelecimentos de saúde de uma cidade, do cadastro ' \
               'oficial do Ministério da Saúde (CNES): nome, tipo, endereço e telefone.',
    consultas: [
      Autonomia::FerramentasProntas::Consulta.new(
        nome: 'estabelecimentos', descricao: 'os estabelecimentos de saúde da cidade',
        opcionais: [CODIGO_IBGE, CIDADE, UF, TIPO, BUSCA], provedores: [Cnes], validade: 7.days, prazo_por_fonte: 4,
        prazo_total: 8, regra: method(:regra), refinar: method(:refinar), nao_encontrado: NAO_ENCONTRADO
      )
    ],
    limite_diario: 500,
    termos: 'API de dados abertos do Ministério da Saúde (sem chave, sem limite publicado). Sem pessoa física. Cache de 7 dias.'
  )
end

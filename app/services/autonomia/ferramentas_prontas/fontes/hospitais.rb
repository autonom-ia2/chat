# HOSPITAIS E CLÍNICAS (#2858, F4): os estabelecimentos de saúde de uma cidade, do CNES (Cadastro Nacional de
# Estabelecimentos de Saúde, Ministério da Saúde), com filtro opcional pelo tipo de unidade e pelo nome.
#   - a cidade vem pelo código IBGE (7 dígitos, ou os 6 que o CNES usa) ou pelo nome e a UF, conferidos na tabela das
#     sedes municipais (`Municipios`): a cidade que não existe naquele estado é pedido inválido, e nada é consultado;
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
  # O tipo de unidade que o modelo escolhe -> o código do CNES (`/cnes/tipounidades`).
  TIPOS = {
    'hospital' => 5, 'hospital_especializado' => 7, 'hospital_dia' => 62, 'pronto_socorro' => 20,
    'pronto_socorro_especializado' => 21, 'pronto_atendimento' => 73, 'unidade_basica' => 2, 'posto_de_saude' => 1,
    'policlinica' => 4, 'clinica' => 36, 'consultorio' => 22, 'exames_e_diagnostico' => 39, 'farmacia' => 43,
    'caps' => 70, 'centro_de_parto' => 61, 'vacinacao' => 85
  }.freeze

  module_function

  # Cidade obrigatória: o código IBGE, ou o nome com a UF (e o nome tem de ser um município daquela UF).
  def regra(params)
    return if params['codigo_ibge']
    return 'cidade' if params['cidade'].nil?
    return 'uf' if params['uf'].nil?

    'cidade' if Municipios.buscar(params['uf'], params['cidade']).nil?
  end

  def refinar(dados, params)
    achados = Autonomia::FerramentasProntas::Lista.filtrar(Array(dados['estabelecimentos']), params['busca']) { |item| item['nome'] }
    return if achados.empty?

    dados.except('estabelecimentos').merge(Autonomia::FerramentasProntas::Lista.cortar(achados, 'estabelecimentos', MAX_ESTABELECIMENTOS))
  end

  CODIGO_IBGE = Parametro.new(nome: 'codigo_ibge', descricao: 'O código IBGE da cidade (7 dígitos), se já souber. Opcional.') do |valor|
    digitos = valor.to_s.delete("^#{Parametro::DIGITOS}")
    codigo = digitos.length == 7 ? digitos[0, 6] : digitos
    codigo if codigo.length == Municipios::DIGITOS_CNES && Municipios.por_codigo_cnes(codigo)
  end
  CIDADE = Parametro.new(nome: 'cidade', descricao: 'O nome da cidade (ex.: Campinas). Vai com a uf.') { |valor| Parametro.texto_curto(valor) }
  UF = Parametro.new(nome: 'uf', descricao: 'A sigla do estado da cidade (ex.: sp).',
                     opcoes: Autonomia::FerramentasProntas::Ufs::SIGLAS.map(&:downcase))
  TIPO = Parametro.new(nome: 'tipo', descricao: 'O tipo de unidade, se o cliente pediu um. Opcional.', opcoes: TIPOS.keys)
  BUSCA = Parametro.new(nome: 'busca', local: true, descricao: 'Parte do nome do estabelecimento. Opcional.') do |valor|
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
        prazo_total: 5, regra: method(:regra), refinar: method(:refinar)
      )
    ],
    limite_diario: 500,
    termos: 'API de dados abertos do Ministério da Saúde (sem chave, sem limite publicado). Sem pessoa física. Cache de 7 dias.'
  )
end

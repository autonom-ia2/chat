# PRODUTOS DAS SEGURADORAS (#2858, F4): os produtos e as coberturas que as seguradoras publicam no Open Insurance Brasil
# (a fase 1, de dados abertos, sem token), só em seguro garantia (setor público e privado) e transporte. O agente
# escolhe a consulta pelo sentido:
#   - seguradoras: quem publica produtos, com busca pelo nome (e, achada a seguradora, os ramos que ela publica);
#   - produtos: os produtos de uma seguradora num ramo (o modelo escolhe o ramo da lista), com busca pelo nome do
#     produto ou pelas coberturas ("carga" acha o RCF-DC, que só diz "carga" na cobertura).
# Decisão do Rodrigo (11/11/2026): a fonte fica no catálogo para os agentes de seguro garantia e de transporte (#2881),
# mas sai da vitrine como card avulso (`na_vitrine: false`). Só os três ramos em que a medição deu catálogo bom
# (`docs/audit/2026-11-11-open-insurance-estudo/MEDICAO.md`); os outros 24 saíram. O mercado está incompleto: parte das
# seguradoras de garantia não publica, e o texto ao agente diz isso.
# O endereço de cada seguradora sai SEMPRE do diretório oficial (`produtos_seguradoras/diretorio.rb`), nunca do código:
# o diretório é baixado inteiro (2 MB), resumido e guardado por horas; a seguradora é chamada no endereço que ele dá
# (`produtos_seguradoras/seguradora.rb`), com prazo curto, e a que não responde sai citada em `nao_responderam`. O
# servidor de teste, o link de exemplo e o produto de sandbox saem antes de chegar ao agente
# (`produtos_seguradoras/sujeira.rb`).
# Termos: Open Insurance Brasil, dados abertos da fase 1, sem chave; sem limite publicado. Cache de 6 horas no diretório
# e de 3 horas nos produtos (a seguradora que falhou numa resposta parcial volta em até 3 horas).
module Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta
  Lista = Autonomia::FerramentasProntas::Lista

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MAX_SEGURADORAS = 50
  MAX_PRODUTOS = 10
  MAX_COBERTURAS = 6
  # O ramo que o modelo escolhe -> a família `products-services_<família>` do Open Insurance e o rótulo da resposta.
  RAMOS = {
    'garantia_publica' => ['public-guarantee', 'Seguro garantia (setor público)'],
    'garantia_privada' => ['private-guarantee', 'Seguro garantia (setor privado)'],
    'transporte' => %w[transport Transportes]
  }.freeze
  # O que o cache guardava antes (v1: 27 ramos, sem o filtro de sujeira) deixa de ser lido.
  VERSAO_DO_CACHE = 2

  module_function

  def rotulo(ramo)
    RAMOS.fetch(ramo).last
  end

  # A família do diretório -> o ramo da lista; nil quando não é uma das famílias atendidas aqui.
  def ramo_da_familia(familia)
    RAMOS.find { |_ramo, (codigo, _rotulo)| "products-services_#{codigo}" == familia }&.first
  end

  # As seguradoras do índice com todas as palavras da busca no nome de marca ou no nome da empresa.
  def achar(indice, busca)
    Lista.filtrar(indice, busca) { |item| "#{item['nome']} #{item['empresa']}" }
  end

  # Sem busca, só os nomes (a lista inteira de ramos de todas passaria do tamanho que o modelo lê); com busca, os ramos.
  def refinar_seguradoras(dados, params)
    achadas = achar(dados['seguradoras'], params['busca'])
    return if achadas.empty?

    itens = achadas.map do |item|
      params['busca'] ? { 'nome' => item['nome'], 'ramos' => item['ramos'].map { |ramo| rotulo(ramo) } } : item['nome']
    end
    Lista.cortar(itens, 'seguradoras', MAX_SEGURADORAS)
  end

  # A busca roda sobre o que veio (ou o cache), no nome do produto e nas coberturas, e cada seguradora mostra no máximo
  # MAX_PRODUTOS.
  def refinar_produtos(dados, params)
    return dados if dados['seguradoras'].blank?

    seguradoras = dados['seguradoras'].map do |item|
      achados = Lista.filtrar(item['produtos'], params['busca']) { |produto| [produto['nome'], *produto['coberturas']].join(' ') }
      item.except('produtos').merge(Lista.cortar(achados, 'produtos', MAX_PRODUTOS))
    end
    return if seguradoras.all? { |item| item['total'].zero? } && params['busca']

    dados.merge('seguradoras' => seguradoras)
  end

  BUSCA = Parametro.new(
    nome: 'busca', local: true,
    descricao: 'Parte do nome: da seguradora, na consulta seguradoras; do produto ou da cobertura (ex.: carga), na consulta ' \
               'produtos. Opcional.'
  ) { |valor| Parametro.texto_curto(valor) }
  SEGURADORA = Parametro.new(nome: 'seguradora', descricao: 'O nome da seguradora como o cliente disse (ex.: Allianz).',
                             pergunte: 'de qual seguradora') do |valor|
    texto = Parametro.texto_curto(valor)
    texto if texto && texto.length >= 2
  end
  RAMO = Parametro.new(nome: 'ramo', descricao: 'O ramo do seguro, da lista.', opcoes: RAMOS.keys,
                       deduza: 'escolha da lista o ramo do tipo de seguro que o cliente disse.')

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'produtos_seguradoras', slug: 'pronta_produtos_seguradoras', nome: 'Produtos das seguradoras', flag: FLAG,
    na_vitrine: false,
    descricao: 'Os produtos e as coberturas de seguro garantia (setor público e privado) e de transporte, entre as ' \
               'seguradoras que publicam no Open Insurance Brasil (dado oficial e aberto). O mercado não está todo aí: ' \
               'Junto, Pottencial, Akad e Fairfax, entre outras, não publicam; nunca diga que só essas fazem o seguro. ' \
               'Não tem preço nem cotação.',
    consultas: [
      Consulta.new(nome: 'seguradoras', descricao: 'as seguradoras que publicam produtos; com busca, os ramos de cada uma',
                   opcionais: [BUSCA], provedores: [OpenInsurance], validade: 6.hours, prazo_por_fonte: 5, prazo_total: 5,
                   refinar: method(:refinar_seguradoras), versao_do_cache: VERSAO_DO_CACHE),
      Consulta.new(nome: 'produtos', descricao: 'os produtos de uma seguradora num ramo; pede seguradora e ramo',
                   obrigatorios: [SEGURADORA, RAMO], opcionais: [BUSCA], provedores: [OpenInsurance], validade: 3.hours,
                   prazo_por_fonte: 4, prazo_total: 10, refinar: method(:refinar_produtos), versao_do_cache: VERSAO_DO_CACHE)
    ],
    limite_diario: 500,
    termos: 'Open Insurance Brasil (dados abertos da fase 1, sem chave e sem limite publicado). Endereço de cada ' \
            'seguradora sempre do diretório oficial; prazo curto por seguradora. Cache de 6 horas no diretório e de 3 nos produtos.'
  )
end

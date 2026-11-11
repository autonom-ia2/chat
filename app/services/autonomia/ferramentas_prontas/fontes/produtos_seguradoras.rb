# PRODUTOS DAS SEGURADORAS (#2858, F4): os produtos e as coberturas que cada seguradora publica no Open Insurance Brasil
# (a fase 1, de dados abertos, sem token). O agente escolhe a consulta pelo sentido:
#   - seguradoras: quem publica produtos, com busca pelo nome (e, achada a seguradora, os ramos que ela publica);
#   - produtos: os produtos de uma seguradora num ramo (o modelo escolhe o ramo da lista), com busca pelo nome do produto.
# O endereço de cada seguradora sai SEMPRE do diretório oficial (`produtos_seguradoras/diretorio.rb`), nunca do código:
# o diretório é baixado inteiro (2 MB), resumido e guardado por horas; a seguradora é chamada no endereço que ele dá
# (`produtos_seguradoras/seguradora.rb`), com prazo curto, e a que não responde sai citada em `nao_responderam`.
# Auto, residencial e condomínio ficam de fora: o endereço deles pede o CEP de pernoite, o código FIPE e o ano (ou a
# área de comercialização), que esta consulta não tem.
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
    'pessoas' => ['person', 'Pessoas (vida, acidentes pessoais, viagem, funeral)'],
    'vida_e_previdencia' => ['life-pension', 'Vida com previdência'],
    'previdencia' => %w[pension-plan Previdência],
    'capitalizacao' => %w[capitalization-title Capitalização],
    'empresarial' => %w[business Empresarial],
    'rural' => %w[rural Rural],
    'habitacional' => %w[housing Habitacional],
    'riscos_ciberneticos' => ['cyber-risk', 'Riscos cibernéticos'],
    'responsabilidade_civil_geral' => ['general-liability', 'Responsabilidade civil geral'],
    'rc_administradores' => ['directors-officers-liability', 'RC de administradores (D&O)'],
    'rc_profissional' => ['errors-omissions-liability', 'RC profissional (E&O)'],
    'rc_ambiental' => ['environmental-liability', 'RC ambiental'],
    'transporte' => %w[transport Transportes],
    'engenharia' => ['engineering', 'Riscos de engenharia'],
    'quebra_de_maquinas' => ['equipment-breakdown', 'Quebra de máquinas e equipamentos'],
    'garantia_publica' => ['public-guarantee', 'Seguro garantia (setor público)'],
    'garantia_privada' => ['private-guarantee', 'Seguro garantia (setor privado)'],
    'fianca_locaticia' => ['rent-guarantee', 'Fiança locatícia'],
    'garantia_estendida' => ['extended-warranty', 'Garantia estendida'],
    'garantia_estendida_auto' => ['auto-extended-warranty', 'Garantia estendida de auto'],
    'lucros_cessantes' => ['lost-profit', 'Lucros cessantes'],
    'riscos_financeiros' => ['financial-risk', 'Riscos financeiros'],
    'credito_interno' => ['domestic-credit', 'Crédito interno'],
    'credito_a_exportacao' => ['export-credit', 'Crédito à exportação'],
    'riscos_nomeados' => ['named-operational-risks', 'Riscos nomeados e operacionais'],
    'global_de_bancos' => ['global-banking', 'Global de bancos'],
    'assistencia_a_bens' => ['assistance-general-assets', 'Assistência a bens em geral']
  }.freeze

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

  # A busca pelo nome do produto roda sobre o que veio (ou o cache), e cada seguradora mostra no máximo MAX_PRODUTOS.
  def refinar_produtos(dados, params)
    return dados if dados['seguradoras'].blank?

    seguradoras = dados['seguradoras'].map do |item|
      achados = Lista.filtrar(item['produtos'], params['busca']) { |produto| produto['nome'] }
      item.except('produtos').merge(Lista.cortar(achados, 'produtos', MAX_PRODUTOS))
    end
    return if seguradoras.all? { |item| item['total'].zero? } && params['busca']

    dados.merge('seguradoras' => seguradoras)
  end

  BUSCA = Parametro.new(
    nome: 'busca', local: true,
    descricao: 'Parte do nome: da seguradora, na consulta seguradoras; do produto, na consulta produtos. Opcional.'
  ) { |valor| Parametro.texto_curto(valor) }
  SEGURADORA = Parametro.new(nome: 'seguradora', descricao: 'O nome da seguradora como o cliente disse (ex.: Allianz).') do |valor|
    texto = Parametro.texto_curto(valor)
    texto if texto && texto.length >= 2
  end
  RAMO = Parametro.new(nome: 'ramo', descricao: 'O ramo do seguro, da lista.', opcoes: RAMOS.keys)

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'produtos_seguradoras', slug: 'pronta_produtos_seguradoras', nome: 'Produtos das seguradoras', flag: FLAG,
    descricao: 'Os produtos e as coberturas que as seguradoras publicam no Open Insurance Brasil (dado oficial e aberto). ' \
               'Não tem preço nem cotação, nem seguro auto, residencial e condomínio.',
    consultas: [
      Consulta.new(nome: 'seguradoras', descricao: 'as seguradoras que publicam produtos; com busca, os ramos de cada uma',
                   opcionais: [BUSCA], provedores: [OpenInsurance], validade: 6.hours, prazo_por_fonte: 5, prazo_total: 5,
                   refinar: method(:refinar_seguradoras)),
      Consulta.new(nome: 'produtos', descricao: 'os produtos de uma seguradora num ramo; pede seguradora e ramo',
                   obrigatorios: [SEGURADORA, RAMO], opcionais: [BUSCA], provedores: [OpenInsurance], validade: 3.hours,
                   prazo_por_fonte: 4, prazo_total: 10, refinar: method(:refinar_produtos))
    ],
    limite_diario: 500,
    termos: 'Open Insurance Brasil (dados abertos da fase 1, sem chave e sem limite publicado). Endereço de cada ' \
            'seguradora sempre do diretório oficial; prazo curto por seguradora. Cache de 6 horas no diretório e de 3 nos produtos.'
  )
end

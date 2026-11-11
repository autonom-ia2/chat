# CÓDIGO DE MERCADORIA (#2858, F4): a NCM (Nomenclatura Comum do Mercosul), o código fiscal que classifica a
# mercadoria na nota, na importação e no imposto. Duas consultas:
#   - buscar: os códigos vigentes com uma palavra (ou parte do código) na descrição, por relevância; vão ao modelo no
#     máximo MAX_ITENS;
#   - codigo: a descrição oficial de um código (2, 4 ou 8 dígitos: capítulo, posição ou o código completo).
#   - fonte única: a BrasilAPI, que repassa a tabela vigente do Siscomex. Sem reserva: o Portal Único (Siscomex) só
#     publica a tabela inteira para baixar (3 MB, `classif/api/publico/nomenclatura/download/json`), não uma consulta.
#     Com a BrasilAPI fora, o agente ouve "não consegui".
#   - a busca vai à fonte (é ela que procura): pede ao menos MIN_BUSCA letras, e a resposta tem teto de 1 MB (a palavra
#     "outros" devolve 600 KB; uma busca mais vaga passa do teto e vira "não consegui").
#   - a fonte acha o GRUPO e não o código da nota (teste em produção, 11/11/2026: "café torrado" devolve só
#     "0901.2 | - Café torrado:"). A busca por palavra devolve o que a fonte trouxe, numa chamada só: os códigos da
#     nota e os grupos (4 a 7 dígitos), com a orientação para o modelo buscar pelo código do grupo. Nenhum ranking
#     nosso escolhe o grupo: quem escolhe é o modelo, pelo sentido da conversa (regra do Rodrigo, revisão do #2917).
#   - a busca pelo código de um grupo ("0901.2") é uma chamada pela posição dele ("search=0901"), que traz os níveis
#     de cima (o material); vão os códigos da nota de dentro do grupo (grupo com mais de MAX_ITENS: os filhos diretos,
#     para o modelo estreitar). Cada código vai com a descrição completa
#     (`Descricao`: "Café, mesmo torrado …, café torrado, não descafeinado").
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real". A tabela muda por resolução da Camex: cache de 7 dias.
module Autonomia::FerramentasProntas::Fontes::Ncm
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MIN_BUSCA = 3
  MAX_ITENS = 20
  MAX_BYTES_BUSCA = 1.megabyte
  TAMANHOS_DO_CODIGO = [2, 4, 8].freeze
  # O código da nota fiscal: 8 dígitos. A posição (4) é onde se procuram os filhos de um grupo; até a subposição (6), o
  # nível de cima diz o que é a mercadoria.
  DA_NOTA = 8
  POSICAO = 4
  SUBPOSICAO = 6
  # O formato do que a NCM guarda no cache (`Consulta#versao_do_cache`): 2 desde os códigos da nota do grupo com a
  # descrição completa (#2858). Só o cache da NCM deixa de valer; o das outras prontas continua.
  VERSAO_DO_CACHE = 2
  # A data de fim da NCM vigente na tabela do Siscomex.
  SEM_FIM = '9999-12-31'.freeze

  module_function

  # "7318.15.00" -> "73181500"; nil fora dos tamanhos que a fonte responde.
  def codigo(valor)
    digitos = valor.to_s.delete("^#{Parametro::DIGITOS}")
    digitos if TAMANHOS_DO_CODIGO.include?(digitos.length) && valor.to_s.delete("#{Parametro::DIGITOS}. ").empty?
  end

  def busca(valor)
    texto = Parametro.texto_curto(valor)
    texto if texto && texto.delete(' ').length >= MIN_BUSCA
  end

  # Os níveis de uma resposta (`Nivel`: cada item lido uma vez). O item fora do formato falha a consulta inteira.
  def niveis(dados)
    dados.map { |dado| Nivel.de(dado) }
  end

  # Os da chamada a mais: o item fora do formato fica de lado, sem derrubar a consulta (revisão do #2917).
  def validos(dados)
    dados.filter_map { |dado| Nivel.ou_nil(dado) }
  end

  # Um item da tabela, enxuto, com a descrição completa (`indice`: os níveis da mesma resposta, `Descricao.indice`).
  def item(nivel, indice = {})
    { 'codigo' => nivel.codigo, 'descricao' => Descricao.completa(nivel, indice), 'vigente_desde' => nivel.vigente_desde }.compact
  end

  # A tabela do Siscomex traz HTML na descrição ("600 g/m<sup>2</sup>", "<i>badminton</i>"): fica o texto, com as
  # entidades decodificadas ("&amp;" -> "&"). A quebra de linha vira espaço: o Nokogiri colava as duas linhas
  # ("linha<br>outra" -> "linhaoutra", revisão do #2891).
  def texto(descricao)
    fragmento = Nokogiri::HTML5.fragment(descricao.to_s)
    fragmento.css('br').each { |quebra| quebra.replace(Nokogiri::XML::Text.new(' ', fragmento.document)) }
    fragmento.text.squish
  end

  # Só o que vale hoje: a tabela também traz o código que já saiu (data de fim no passado).
  def vigente?(dado)
    fim = dado.is_a?(Hash) ? dado['data_fim'].to_s : ''
    fim.empty? || fim == SEM_FIM || fim >= Time.zone.today.iso8601
  end

  # A busca por palavra. A BrasilAPI devolve na ordem do código: a ordem por relevância vem antes do corte (sem ela,
  # "parafuso" mostrava primeiro o 34.03, lubrificantes "antiaderentes de porcas e parafusos", e o 73.18 vinha depois).
  # No mesmo grupo, o código completo (8 dígitos, o da nota) antes da posição (4) e do capítulo (2). Com grupo entre os
  # itens, a orientação para buscar pelo código dele, com o primeiro de exemplo.
  def lista(busca, niveis)
    indice = Descricao.indice(niveis)
    itens = em_ordem(busca, niveis, indice).map { |item, nivel| confira(item, nivel, indice) }
    resposta = { 'busca' => busca }.merge(Autonomia::FerramentasProntas::Lista.cortar(itens, 'itens', MAX_ITENS))
    grupo = resposta['itens'].find { |item| Nivel.grupo?(digitos(item['codigo'])) }
    grupo ? resposta.merge('observacao' => format(BUSQUE_O_GRUPO, grupo: grupo['codigo'])) : resposta
  end

  # O código da nota que veio sem os níveis de cima tem a descrição relativa ("De parafuso", do 8414.40.20): vai marcado
  # (revisão do #2917).
  def confira(item, nivel, indice)
    nivel.da_nota? && !Descricao.inteira?(nivel, indice) ? item.merge('observacao' => CONFIRA) : item
  end

  # -> [[item, nivel], ...] na ordem de relevância, pelo texto do próprio nível: a descrição completa começa pela
  # posição, e com ela todos os filhos do 73.18 começavam por "Parafusos" (o tira-fundos vinha antes do parafuso).
  def em_ordem(busca, niveis, indice)
    pares = niveis.map { |nivel| [item(nivel, indice), nivel] }
    Autonomia::FerramentasProntas::Lista.em_ordem(pares, busca, desempate: ->(par) { -par.last.digitos.length }) do |_item, nivel|
      nivel.propria
    end
  end

  # A busca é o código de um grupo (ou de um código da nota): só dígitos, pontos e espaços, de 4 a 8 dígitos. -> os
  # dígitos, ou nil (a busca é por palavra).
  def grupo_da_busca(busca)
    numeros = digitos(busca)
    numeros if busca.delete("#{Parametro::DIGITOS}. ").empty? && numeros.length.between?(POSICAO, DA_NOTA)
  end

  # Os códigos da nota de dentro do grupo, na resposta da posição dele, na ordem do código. Nenhum: não encontrado.
  # Mais de MAX_ITENS: os filhos diretos do grupo (`para_estreitar`).
  def do_grupo(busca, grupo, achados)
    niveis = validos(achados)
    indice = Descricao.indice(niveis)
    da_nota = niveis.select { |nivel| nivel.da_nota? && nivel.digitos.start_with?(grupo) }
    raise Autonomia::FerramentasProntas::Provedor::NaoEncontrado if da_nota.empty?
    return para_estreitar(busca, grupo, niveis, indice) if da_nota.size > MAX_ITENS

    itens = da_nota.map { |nivel| item(nivel, indice) }
    { 'busca' => busca }.merge(Autonomia::FerramentasProntas::Lista.cortar(itens, 'itens', MAX_ITENS))
  end

  # O grupo grande demais para ir inteiro (a posição 30.04 tem 153 códigos da nota; o corte pela ordem do código
  # mostrava só os 3004.10.xx, revisão do #2917): vão os filhos diretos dele, o subgrupo ou o código da nota sem
  # subgrupo no meio (3004.60.00), com a orientação para o modelo buscar pelo subgrupo que fizer sentido.
  def para_estreitar(busca, grupo, niveis, indice)
    filhos = niveis.select { |nivel| filho?(nivel, grupo, indice) }
    resposta = { 'busca' => busca }.merge(Autonomia::FerramentasProntas::Lista.cortar(filhos.map { |nivel| item(nivel, indice) },
                                                                                      'itens', MAX_ITENS))
    exemplo = filhos.find { |nivel| Nivel.grupo?(nivel.digitos) }
    exemplo ? resposta.merge('observacao' => format(BUSQUE_O_GRUPO, grupo: exemplo.codigo)) : resposta
  end

  # Abaixo do grupo, sem outro nível do grupo no meio.
  def filho?(nivel, grupo, indice)
    numeros = nivel.digitos
    numeros.length > grupo.length && numeros.start_with?(grupo) &&
      ((grupo.length + 1)...numeros.length).none? { |tamanho| indice.key?(numeros.first(tamanho)) }
  end

  # O código de 8 dígitos na resposta da posição dele, com a descrição completa. Fora dela: não encontrado.
  def da_nota(codigo, achados)
    alvo = achados.find { |dado| dado.is_a?(Hash) && digitos(dado['codigo']) == codigo }
    raise Autonomia::FerramentasProntas::Provedor::NaoEncontrado if alvo.nil?

    item(Nivel.de(alvo), Descricao.indice(validos(achados)))
  end

  # Onde procurar os filhos de um código: a posição dele (4 dígitos), que traz também os níveis de cima da descrição.
  def prefixo_da_busca(codigo)
    digitos(codigo).first(POSICAO)
  end

  def digitos(codigo)
    codigo.to_s.delete("^#{Parametro::DIGITOS}")
  end

  # A tabela da NCM tem o termo técnico da nomenclatura: "celular" acha a terapia celular (varredura F24). Quem traduz
  # o que o cliente disse é o modelo; a ordem de relevância de sempre vale sobre o que a busca achar.
  DESCRICAO_DA_BUSCA = 'Na consulta buscar: uma palavra da mercadoria no termo da nomenclatura (ex.: parafuso; telefones ' \
                       'celulares, não celular; máquinas automáticas para processamento de dados, não computador) ou o ' \
                       "código de um grupo (ex.: 0901.2); ao menos #{MIN_BUSCA} letras.".freeze
  BUSCA = Parametro.new(nome: 'busca', descricao: DESCRICAO_DA_BUSCA,
                        deduza: "mande uma palavra do produto, com ao menos #{MIN_BUSCA} letras (ex.: parafuso).") { |valor| busca(valor) }
  CODIGO = Parametro.new(nome: 'codigo', descricao: 'Na consulta codigo: o código NCM, com ou sem pontos (ex.: 7318.15.00).',
                         deduza: 'o código tem 2, 4 ou 8 dígitos; se o cliente disse o produto, use a consulta buscar.') do |valor|
    codigo(valor)
  end

  SO_O_DE_8 = 'Na nota fiscal vai só o código de 8 dígitos; 2 dígitos é o capítulo e 4 é a posição, não servem na nota. ' \
              'Com mais de uma opção de 8 dígitos, pergunte ao cliente o material (aço, cobre, plástico…) antes de ' \
              'dizer o código.'.freeze
  # Na consulta codigo, só quando o código ainda não é o da nota (regra "QI 70": o de 8 dígitos já está certo, e
  # perguntar o material ali seria pergunta à toa).
  NAO_E_O_DA_NOTA = 'Este código tem %<digitos>s dígitos: é o capítulo ou a posição, e não serve na nota fiscal (lá vai o de ' \
                    '8 dígitos). Para chegar ao da nota, pergunte ao cliente o material (aço, cobre, plástico…) e use a ' \
                    'consulta buscar.'.freeze

  # A orientação da busca por palavra com grupo entre os itens. O grupo tem de 4 a 7 dígitos: nunca manda buscar um
  # capítulo. Cada texto cabe inteiro no que vai ao modelo (`Resposta::MAX_TEXTO`).
  BUSQUE_O_GRUPO = 'Código com menos de 8 dígitos é grupo e não vai na nota. Para ver os da nota, faça a consulta buscar ' \
                   'com o código do grupo (ex.: %<grupo>s).'.freeze
  CONFIRA = 'Descrição sem os níveis de cima: confira com a consulta codigo.'.freeze

  # A descrição de um código. Abaixo de 8 dígitos, com a observação de que ainda não é o da nota.
  def self.do_codigo(item, codigo)
    return item if codigo.length == DA_NOTA

    item.merge('observacao' => format(NAO_E_O_DA_NOTA, digitos: codigo.length))
  end

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'ncm', slug: 'pronta_ncm', nome: 'Código de mercadoria', flag: FLAG,
    descricao: 'A NCM, o código fiscal da mercadoria: procura o código pelo nome do produto ou diz o que um código é.',
    consultas: [
      Consulta.new(nome: 'buscar', descricao: "os códigos de uma mercadoria; pede busca. #{SO_O_DE_8}", obrigatorios: [BUSCA],
                   provedores: [BrasilApi], validade: 7.days, prazo_por_fonte: 4, prazo_total: 4, versao_do_cache: VERSAO_DO_CACHE),
      Consulta.new(nome: 'codigo', descricao: 'a descrição oficial de um código; pede codigo', obrigatorios: [CODIGO],
                   provedores: [BrasilApi], validade: 7.days, prazo_por_fonte: 4, prazo_total: 4, versao_do_cache: VERSAO_DO_CACHE)
    ],
    limite_diario: 500,
    termos: 'BrasilAPI (uso de pessoa real), que repassa a tabela do Siscomex; sem reserva (o Siscomex só publica o ' \
            'arquivo inteiro). Cache de 7 dias.'
  )
end

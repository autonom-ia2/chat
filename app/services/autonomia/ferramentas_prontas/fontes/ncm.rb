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
#     "0901.2 | - Café torrado:"). O grupo mais relevante (menos de 8 dígitos) abre nos códigos de 8 dígitos dele, com
#     uma chamada a mais pela posição ("search=0901"), dentro do mesmo prazo. Cada código vai com a descrição completa
#     (`Descricao`: "Café torrado, não descafeinado"). Sem tempo para a chamada a mais: o que veio, com a observação.
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real". A tabela muda por resolução da Camex: cache de 7 dias.
module Autonomia::FerramentasProntas::Fontes::Ncm
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MIN_BUSCA = 3
  MAX_ITENS = 20
  MAX_BYTES_BUSCA = 1.megabyte
  TAMANHOS_DO_CODIGO = [2, 4, 8].freeze
  # O código da nota fiscal: 8 dígitos. A posição (4) é onde se procuram os filhos de um grupo.
  DA_NOTA = 8
  POSICAO = 4
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

  # A BrasilAPI devolve na ordem do código: a ordem por relevância vem antes do corte (sem ela, "parafuso" mostrava
  # primeiro o 34.03, lubrificantes "antiaderentes de porcas e parafusos", e o 73.18 vinha depois). No mesmo grupo, o
  # código completo (8 dígitos, o da nota) antes da posição (4) e do capítulo (2).
  def lista(busca, niveis, indice = Descricao.indice(niveis))
    itens = em_ordem(busca, niveis, indice).map(&:first)
    { 'busca' => busca }.merge(Autonomia::FerramentasProntas::Lista.cortar(itens, 'itens', MAX_ITENS))
  end

  # -> [[item, nivel], ...] na ordem de relevância. Vale o melhor entre a descrição completa e a do próprio nível:
  # "Parafusos autoperfurantes" começa pela palavra, "Artigos roscados, parafusos autoperfurantes" não.
  def em_ordem(busca, niveis, indice)
    pares = niveis.map { |nivel| [item(nivel, indice), nivel] }
    Autonomia::FerramentasProntas::Lista.em_ordem(pares, busca, desempate: ->(par) { -par.last.digitos.length }) do |item, nivel|
      [item['descricao'], nivel.propria]
    end
  end

  # O grupo (menos de 8 dígitos) mais relevante que a busca trouxe: é ele que abre. No mesmo grupo de relevância, o mais
  # largo (a posição antes da subposição: abre mais códigos da nota). nil quando só veio código da nota.
  def grupo_a_abrir(busca, niveis)
    indice = Descricao.indice(niveis)
    grupos = niveis.reject(&:da_nota?)
    Autonomia::FerramentasProntas::Lista.em_ordem(grupos, busca, desempate: ->(nivel) { nivel.digitos.length }) do |nivel|
      [Descricao.completa(nivel, indice), nivel.propria]
    end.first
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

  # O grupo aberto: no lugar dele, os códigos da nota que ele tem (`descendentes`: o que a chamada a mais trouxe), com a
  # descrição completa. Grupo sem código da nota embaixo: fica o grupo. `descendentes` nil (a chamada a mais não veio a
  # tempo): a busca como veio, com a observação.
  def aberta(busca, niveis, grupo, descendentes)
    return lista(busca, niveis).merge('observacao' => SEM_OS_DA_NOTA) if descendentes.nil?

    de_baixo = validos(descendentes)
    indice = Descricao.indice(niveis + de_baixo)
    da_nota = de_baixo.select { |nivel| nivel.da_nota? && nivel.digitos.start_with?(grupo.digitos) }
    return lista(busca, niveis, indice) if da_nota.empty?

    lista(busca, no_lugar_do_grupo(niveis, grupo, da_nota), indice)
  end

  # No lugar do grupo, os códigos da nota dele. O que mais era do grupo sai (volta entre os da nota, se for da nota).
  def no_lugar_do_grupo(niveis, grupo, da_nota)
    niveis.flat_map do |nivel|
      next da_nota if nivel.equal?(grupo)

      nivel.digitos.start_with?(grupo.digitos) ? [] : [nivel]
    end
  end

  def digitos(codigo)
    codigo.to_s.delete("^#{Parametro::DIGITOS}")
  end

  # A tabela da NCM tem o termo técnico da nomenclatura: "celular" acha a terapia celular (varredura F24). Quem traduz
  # o que o cliente disse é o modelo; a ordem de relevância de sempre vale sobre o que a busca achar.
  DESCRICAO_DA_BUSCA = 'Na consulta buscar: uma palavra da mercadoria no termo da nomenclatura (ex.: parafuso; telefones ' \
                       'celulares, não celular; máquinas automáticas para processamento de dados, não computador) ou parte ' \
                       "do código; ao menos #{MIN_BUSCA} letras.".freeze
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

  # A resposta incompleta (a chamada a mais não veio a tempo): vai ao modelo com o que veio, e fica fora do cache. Cada
  # uma cabe no texto que vai ao modelo (`Resposta::MAX_TEXTO`).
  SEM_OS_DA_NOTA = 'Os códigos de 8 dígitos do grupo não vieram a tempo, e o grupo não vai na nota: faça a consulta ' \
                   'buscar com o código do grupo.'.freeze
  INCOMPLETAS = [SEM_OS_DA_NOTA].freeze

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

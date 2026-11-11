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
# Termos: BrasilAPI pede uso com "natureza de uma pessoa real". A tabela muda por resolução da Camex: cache de 7 dias.
module Autonomia::FerramentasProntas::Fontes::Ncm
  Parametro = Autonomia::FerramentasProntas::Parametro
  Consulta = Autonomia::FerramentasProntas::Consulta

  FLAG = 'agente_ferramentas_prontas_lote2'.freeze
  MIN_BUSCA = 3
  MAX_ITENS = 20
  MAX_BYTES_BUSCA = 1.megabyte
  TAMANHOS_DO_CODIGO = [2, 4, 8].freeze
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

  # Um item da tabela, enxuto. Sem código ou descrição: falha, e o agente ouve "não consegui".
  def item(dado)
    falha = Autonomia::FerramentasProntas::Provedor::Falha
    raise falha, 'resposta_invalida' unless dado.is_a?(Hash) && dado['codigo'].present? && dado['descricao'].present?

    { 'codigo' => dado['codigo'].to_s.strip, 'descricao' => dado['descricao'].to_s.squish, 'vigente_desde' => dado['data_inicio'].presence }.compact
  end

  # Só o que vale hoje: a tabela também traz o código que já saiu (data de fim no passado).
  def vigente?(dado)
    fim = dado.is_a?(Hash) ? dado['data_fim'].to_s : ''
    fim.empty? || fim == SEM_FIM || fim >= Time.zone.today.iso8601
  end

  # A BrasilAPI devolve na ordem do código: a ordem por relevância vem antes do corte (sem ela, "parafuso" mostrava
  # primeiro o 34.03, lubrificantes "antiaderentes de porcas e parafusos", e o 73.18 vinha depois). No mesmo grupo, o
  # código completo (8 dígitos, o da nota) antes da posição (4) e do capítulo (2).
  def lista(busca, itens)
    lista = Autonomia::FerramentasProntas::Lista
    ordem = lista.em_ordem(itens, busca, desempate: ->(item) { -digitos(item['codigo']).length }) { |item| item['descricao'] }
    { 'busca' => busca }.merge(lista.cortar(ordem, 'itens', MAX_ITENS))
  end

  def digitos(codigo)
    codigo.to_s.delete("^#{Parametro::DIGITOS}")
  end

  DESCRICAO_DA_BUSCA = "Na consulta buscar: uma palavra da mercadoria (ex.: parafuso) ou parte do código; ao menos #{MIN_BUSCA} " \
                       'letras.'.freeze
  BUSCA = Parametro.new(nome: 'busca', descricao: DESCRICAO_DA_BUSCA) { |valor| busca(valor) }
  CODIGO = Parametro.new(nome: 'codigo', descricao: 'Na consulta codigo: o código NCM, com ou sem pontos (ex.: 7318.15.00).') do |valor|
    codigo(valor)
  end

  SO_O_DE_8 = 'Na nota fiscal vai só o código de 8 dígitos; 2 dígitos é o capítulo e 4 é a posição, não servem na nota. ' \
              'Com mais de uma opção de 8 dígitos, pergunte ao cliente o material (aço, cobre, plástico…) antes de ' \
              'dizer o código.'.freeze

  FONTE = Autonomia::FerramentasProntas::Fonte.new(
    chave: 'ncm', slug: 'pronta_ncm', nome: 'Código de mercadoria', flag: FLAG,
    descricao: 'A NCM, o código fiscal da mercadoria: procura o código pelo nome do produto ou diz o que um código é.',
    consultas: [
      Consulta.new(nome: 'buscar', descricao: "os códigos de uma mercadoria; pede busca. #{SO_O_DE_8}", obrigatorios: [BUSCA],
                   provedores: [BrasilApi], validade: 7.days, prazo_por_fonte: 4, prazo_total: 4),
      Consulta.new(nome: 'codigo', descricao: "a descrição oficial de um código; pede codigo. #{SO_O_DE_8}", obrigatorios: [CODIGO],
                   provedores: [BrasilApi], validade: 7.days, prazo_por_fonte: 4, prazo_total: 4)
    ],
    limite_diario: 500,
    termos: 'BrasilAPI (uso de pessoa real), que repassa a tabela do Siscomex; sem reserva (o Siscomex só publica o ' \
            'arquivo inteiro). Cache de 7 dias.'
  )
end

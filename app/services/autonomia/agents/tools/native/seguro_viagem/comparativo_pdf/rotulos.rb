# OS RÓTULOS dos planos no comparativo (#3211): uma regra fixa, sem opinião do modelo, para o cliente ver o porquê.
#
# - MAIS ECONÔMICA: o menor `preco_total`; empate, mais despesas médicas; persistindo, a ordem dos planos.
# - MAIOR COBERTURA: o maior valor de despesas médicas e hospitalares (a cobertura de `Planos::IDS_DMH`); empate, o
#   menor preço; persistindo, a ordem dos planos. Se for a mesma da econômica, fica só "mais econômica".
# - MAIS RECOMENDADA: `recomendada`, pela pontuação (`Pontuacao`): a de mais pontos entre as que não são a econômica
#   nem a de maior cobertura. Sem nenhuma assim (2 planos, um em cada ponta), a de mais pontos vira a recomendada e
#   perde o rótulo de ponta; a outra fica com o dela.
# - Com 1 plano: "opção disponível".
# Cada plano tem no máximo um rótulo.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  NOMES = {
    economica: 'Mais econômica', recomendada: 'Mais recomendada', maior_cobertura: 'Maior cobertura',
    disponivel: 'Opção disponível'
  }.freeze
  MEDICO_E_HOSPITAL = 'médico e hospital'.freeze

  module_function

  # -> um símbolo de `NOMES` (ou nil) por plano, na ordem dos planos.
  def de(planos)
    return [] if planos.empty?
    return [:disponivel] if planos.size == 1

    recomendada = recomendada(planos)
    economica = economica(planos)
    maior = maior_cobertura(planos)
    maior = nil if [recomendada, economica].include?(maior)
    economica = nil if economica == recomendada
    Array.new(planos.size) do |indice|
      { recomendada => :recomendada, economica => :economica, maior => :maior_cobertura }[indice]
    end
  end

  # A REGRA DA RECOMENDADA: -> o índice do plano recomendado (nil sem planos). Os planos em ordem de pontuação (mais
  # pontos, depois mais despesas médicas, depois menor preço); o 1º que não é a econômica nem a de maior cobertura, ou,
  # sem nenhum assim, o 1º de todos.
  def recomendada(planos)
    return nil if planos.empty?
    return 0 if planos.size == 1

    ordem = por_pontuacao(planos)
    extremos = [economica(planos), maior_cobertura(planos)]
    ordem.find { |indice| extremos.exclude?(indice) } || ordem.first
  end

  # -> a pontuação de cada plano, na ordem dos planos (`Pontuacao.de`).
  def pontuacoes(planos)
    return [] if planos.empty?

    economica = economica(planos)
    maior = maior_cobertura(planos)
    SeguroViagem::ComparativoPdf::Pontuacao.de(planos, economica: economica, maior: maior == economica ? nil : maior)
  end

  # O valor de despesas médicas como número (`'R$ 100.000'` -> 100000); sem a cobertura, 0.
  def despesas_medicas(plano)
    inteiro = despesas_medicas_texto(plano).to_s.split(',').first.to_s
    algarismos = inteiro.each_char.select { |letra| letra.between?('0', '9') }.join
    algarismos.empty? ? 0 : algarismos.to_i
  end

  # O texto da cobertura de despesas médicas como a Universal escreve, ou nil.
  def despesas_medicas_texto(plano)
    cobertura = plano['coberturas'].to_a.find { |item| SeguroViagem::Planos::IDS_DMH.include?(item['id_beneficio']) }
    cobertura.to_h['valor'].to_s.strip.presence || plano.dig('principais', 'despesas_medicas').presence
  end

  # "R$ 100.000 para médico e hospital": o mesmo nome em todo o documento. Sem a cobertura, diz que não veio.
  def para_medico_e_hospital(plano)
    valor = despesas_medicas_texto(plano)
    valor.nil? ? 'Médico e hospital: não informado' : "#{valor} para #{MEDICO_E_HOSPITAL}"
  end

  # O PORQUÊ do plano em destaque, só com números da cotação (`planos` e `rotulos` na mesma ordem). Compara com a
  # opção mais barata só quando ela existe e é outra; a de maior cobertura entra só se for outra e custar mais.
  def porque(planos, rotulos)
    indice = rotulos.index(:recomendada)
    return disponivel(planos.first) if indice.nil?

    plano = planos[indice]
    return disponivel(plano) unless preco(plano).finite?

    [frente_a_mais_barata(plano, planos[economica(planos)]),
     frente_a_maior(plano, planos[rotulos.index(:maior_cobertura) || indice])].compact.join(' ')
  end

  def disponivel(plano)
    return '' if plano.nil?

    total = "#{brl(preco(plano))} no total."
    despesas_medicas_texto(plano).nil? ? total.upcase_first : "#{para_medico_e_hospital(plano)} por #{total}"
  end

  def frente_a_mais_barata(plano, barata)
    dmh = despesas_medicas_texto(plano)
    unless preco(barata) < preco(plano)
      return "É a opção mais barata desta cotação#{", com #{dmh} para #{MEDICO_E_HOSPITAL}" if dmh}."
    end

    diferenca = brl(preco(plano) - preco(barata))
    dmh_da_barata = despesas_medicas_texto(barata)
    if dmh && dmh_da_barata && despesas_medicas(barata) < despesas_medicas(plano)
      return "Por #{diferenca} a mais que a opção mais barata, a proteção para #{MEDICO_E_HOSPITAL} sobe de " \
             "#{dmh_da_barata} para #{dmh}."
    end

    "Custa #{diferenca} a mais que a opção mais barata#{", com #{dmh} para #{MEDICO_E_HOSPITAL}" if dmh}."
  end

  def frente_a_maior(plano, maior)
    return nil unless preco(maior) > preco(plano) && preco(maior).finite?

    "A de maior cobertura custa #{brl(preco(maior) - preco(plano))} a mais."
  end

  def economica(planos)
    planos.each_index.min_by { |indice| [preco(planos[indice]), -despesas_medicas(planos[indice]), indice] }
  end

  def maior_cobertura(planos)
    planos.each_index.min_by { |indice| [-despesas_medicas(planos[indice]), preco(planos[indice]), indice] }
  end

  def por_pontuacao(planos)
    pontos = pontuacoes(planos)
    planos.each_index.sort_by do |indice|
      [-pontos[indice], -despesas_medicas(planos[indice]), preco(planos[indice]), indice]
    end
  end

  # Sem preço o plano nunca é o mais barato.
  def preco(plano)
    plano['preco_total'].blank? ? Float::INFINITY : BigDecimal(plano['preco_total'].to_s)
  end

  def brl(valor)
    valor.finite? ? SeguroViagem::Dinheiro.brl(valor) : 'valor não informado'
  end

  private_class_method :disponivel, :frente_a_mais_barata, :frente_a_maior, :economica, :maior_cobertura, :por_pontuacao,
                       :preco, :brl
end

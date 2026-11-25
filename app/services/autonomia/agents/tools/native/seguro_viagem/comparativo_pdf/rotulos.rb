# OS RÓTULOS dos planos no comparativo (#3211): uma regra fixa, sem opinião do modelo, para o cliente ver o porquê.
#
# - MAIS RECOMENDADA: a regra de `recomendada`, isolada para poder ser trocada sem mexer no resto.
# - MAIS ECONÔMICA: o menor `preco_total`, se não for a recomendada.
# - MAIOR COBERTURA: o maior valor de despesas médicas e hospitalares (a cobertura de `Planos::IDS_DMH`), se não for a
#   recomendada nem a econômica.
# - Com 1 plano: "opção disponível".
# Cada plano tem no máximo um rótulo. Empate: o menor preço vence; persistindo, a ordem dos planos.
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

    indices = (0...planos.size).to_a
    recomendada = recomendada(planos)
    economica = mais_barato(planos, indices)
    economica = nil if economica == recomendada
    maior = maior_cobertura(planos, indices)
    maior = nil if [recomendada, economica].include?(maior)
    Array.new(planos.size) do |indice|
      { recomendada => :recomendada, economica => :economica, maior => :maior_cobertura }[indice]
    end
  end

  # A REGRA DA RECOMENDADA (a única coisa a trocar quando a regra mudar): -> o índice do plano recomendado.
  # Hoje: com 2 planos, o de mais despesas médicas por real pago (despesas médicas ÷ preço total); com 3 ou mais, o
  # mesmo critério entre os planos que não são o mais barato nem o de maior cobertura.
  def recomendada(planos)
    indices = (0...planos.size).to_a
    return indices.first if planos.size < 2

    extremos = planos.size == 2 ? [] : [mais_barato(planos, indices), maior_cobertura(planos, indices)]
    melhor_por_real(planos, indices - extremos)
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

    [frente_a_mais_barata(plano, planos[mais_barato(planos, (0...planos.size).to_a)]),
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

  def mais_barato(planos, indices)
    indices.min_by { |indice| [preco(planos[indice]), indice] }
  end

  def maior_cobertura(planos, indices)
    indices.min_by { |indice| [-despesas_medicas(planos[indice]), preco(planos[indice]), indice] }
  end

  def melhor_por_real(planos, indices)
    indices.min_by { |indice| [-por_real(planos[indice]), preco(planos[indice]), indice] }
  end

  def por_real(plano)
    total = preco(plano)
    total.positive? && total.finite? ? despesas_medicas(plano) / total : 0
  end

  # Sem preço o plano nunca é o mais barato.
  def preco(plano)
    plano['preco_total'].blank? ? Float::INFINITY : BigDecimal(plano['preco_total'].to_s)
  end

  def brl(valor)
    valor.finite? ? SeguroViagem::Dinheiro.brl(valor) : 'valor não informado'
  end

  private_class_method :disponivel, :frente_a_mais_barata, :frente_a_maior, :mais_barato, :maior_cobertura,
                       :melhor_por_real, :por_real, :preco, :brl
end

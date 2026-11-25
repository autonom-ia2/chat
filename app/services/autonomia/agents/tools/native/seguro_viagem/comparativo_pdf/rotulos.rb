# OS RÓTULOS dos planos no comparativo (#3211): uma regra fixa, sem opinião do modelo, para o cliente ver o porquê.
#
# - MAIS ECONÔMICA: o menor `preco_total`.
# - MAIOR COBERTURA: o maior valor de despesas médicas e hospitalares (a cobertura de `Planos::IDS_DMH`). Se for o
#   mesmo plano da mais econômica, ele fica só com "mais econômica" e ninguém leva "maior cobertura".
# - MAIS RECOMENDADA: entre os planos que não são os dois extremos, o de mais despesas médicas por real pago
#   (despesas médicas ÷ preço total).
# - Com 2 planos: a recomendada é a de mais despesas médicas por real entre os dois; o outro leva o rótulo que lhe
#   couber (econômica ou maior cobertura), ou nenhum.
# - Com 1 plano: "opção disponível".
# Cada plano tem no máximo um rótulo. Empate: o menor preço vence; persistindo, a ordem da Universal.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem
  NOMES = {
    economica: 'Mais econômica', recomendada: 'Mais recomendada', maior_cobertura: 'Maior cobertura',
    disponivel: 'Opção disponível'
  }.freeze
  ORDEM_DO_RESUMO = %i[economica recomendada maior_cobertura].freeze

  module_function

  # -> um símbolo de `NOMES` (ou nil) por plano, na ordem dos planos.
  def de(planos)
    case planos.size
    when 0 then []
    when 1 then [:disponivel]
    when 2 then de_dois(planos)
    else de_varios(planos)
    end
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

  # A frase do porquê, fixa por rótulo e só com números do plano.
  def frase(rotulo, plano)
    dmh = despesas_medicas_texto(plano) || '—'
    preco = plano['preco_total'].blank? ? '—' : SeguroViagem::Dinheiro.brl(plano['preco_total'])
    case rotulo
    when :economica then "O menor preço desta cotação: #{preco} no total, com #{dmh} de despesas médicas."
    when :maior_cobertura then "A maior cobertura de despesas médicas desta cotação: #{dmh}, por #{preco} no total."
    when :recomendada then "Equilibra proteção e preço: #{dmh} de despesas médicas por #{preco} no total."
    else "#{dmh} de despesas médicas por #{preco} no total."
    end
  end

  def de_dois(planos)
    indices = [0, 1]
    recomendada = melhor_por_real(planos, indices)
    outro = (indices - [recomendada]).first
    rotulo_do_outro = if outro == mais_barato(planos, indices) then :economica
                      elsif outro == maior_cobertura(planos, indices) then :maior_cobertura
                      end
    montar(2, recomendada => :recomendada, outro => rotulo_do_outro)
  end

  def de_varios(planos)
    indices = (0...planos.size).to_a
    economica = mais_barato(planos, indices)
    maior = maior_cobertura(planos, indices)
    maior = nil if maior == economica
    recomendada = melhor_por_real(planos, indices - [economica, maior])
    montar(planos.size, economica => :economica, maior => :maior_cobertura, recomendada => :recomendada)
  end

  def montar(quantos, por_indice)
    Array.new(quantos) { |indice| por_indice[indice] }
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

  private_class_method :de_dois, :de_varios, :montar, :mais_barato, :maior_cobertura, :melhor_por_real, :por_real, :preco
end

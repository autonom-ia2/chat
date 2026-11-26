# A PONTUAÇÃO que escolhe a mais recomendada no comparativo (#3211): pontuação do fluxo de cotação da GTA (n8n),
# aprovada pelo Rodrigo em 25/11; sem os termos que a Universal não traz (Sala VIP, desconto familiar, sênior, banda de
# cobertura configurada). Função pura: cada plano parte de `PARTIDA` e soma
# - PREÇO frente à mais econômica (r = preço ÷ preço da econômica): quanto mais perto, mais pontos;
# - COBERTURA frente à mais econômica (c = despesas médicas ÷ as da econômica): quanto mais proteção, mais pontos;
# - EFICIÊNCIA (e = índice ÷ melhor índice; índice = preço ÷ despesas médicas × 1000): real por proteção;
# - o desconto de ser a própria econômica, e o de ser a de maior cobertura (maior se ela custa mais que o dobro).
# Termo que não dá para calcular (sem preço, sem despesas médicas) não soma nem tira.
module Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Pontuacao
  PARTIDA = 30
  # [limite, pontos]: r até o limite ganha os pontos; acima do último, `PRECO_ACIMA`.
  PRECO = [[BigDecimal('1.15'), 8], [BigDecimal('1.45'), 6], [BigDecimal('1.85'), 2]].freeze
  PRECO_ACIMA = -5
  # [limite, pontos]: c a partir do limite ganha os pontos; abaixo de `COBERTURA_BAIXA`, `COBERTURA_BAIXA_PONTOS`.
  COBERTURA = [[BigDecimal(4), 20], [BigDecimal('2.5'), 12], [BigDecimal('1.5'), 6]].freeze
  COBERTURA_BAIXA = BigDecimal('1.2')
  COBERTURA_BAIXA_PONTOS = -8
  # [limite, pontos]: e até o limite ganha os pontos; acima do último, `EFICIENCIA_ABAIXO`.
  EFICIENCIA = [[BigDecimal('1.05'), 28], [BigDecimal('1.20'), 18], [BigDecimal('1.40'), 8]].freeze
  EFICIENCIA_ABAIXO = -8
  ESCALA_DO_INDICE = 1000
  SENDO_A_ECONOMICA = -10
  SENDO_A_MAIOR = -4
  SENDO_A_MAIOR_CARA = -14
  MAIOR_CARA_A_PARTIR_DE = 2

  module_function

  # -> a pontuação (inteiro) de cada plano, na ordem dos planos. `economica` e `maior` são os índices desses rótulos.
  def de(planos, economica:, maior:)
    indices = planos.map { |plano| indice(plano) }
    melhor = indices.compact.min
    base = planos[economica]
    planos.each_with_index.map do |plano, posicao|
      razao = razao(preco(plano), preco(base))
      PARTIDA + pontos_do_preco(razao) + pontos_da_cobertura(plano, base) + pontos_da_eficiencia(indices[posicao], melhor) +
        (posicao == economica ? SENDO_A_ECONOMICA : 0) + (posicao == maior ? desconto_da_maior(razao) : 0)
    end
  end

  # preço ÷ despesas médicas × 1000; nil sem preço ou sem despesas médicas.
  def indice(plano)
    dmh = despesas_medicas(plano)
    return nil if preco(plano).nil? || !dmh.positive?

    preco(plano) / dmh * ESCALA_DO_INDICE
  end

  def pontos_do_preco(razao)
    return 0 if razao.nil?

    PRECO.find { |limite, _| razao <= limite }&.last || PRECO_ACIMA
  end

  def pontos_da_cobertura(plano, base)
    razao = razao(BigDecimal(despesas_medicas(plano)), BigDecimal(despesas_medicas(base)))
    return 0 if razao.nil?

    pontos = COBERTURA.find { |limite, _| razao >= limite }&.last
    return pontos unless pontos.nil?

    razao < COBERTURA_BAIXA ? COBERTURA_BAIXA_PONTOS : 0
  end

  def pontos_da_eficiencia(indice, melhor)
    razao = indice.nil? ? nil : razao(indice, melhor)
    return 0 if razao.nil?

    EFICIENCIA.find { |limite, _| razao <= limite }&.last || EFICIENCIA_ABAIXO
  end

  def desconto_da_maior(razao)
    !razao.nil? && razao > MAIOR_CARA_A_PARTIR_DE ? SENDO_A_MAIOR_CARA : SENDO_A_MAIOR
  end

  # a ÷ b; nil quando não dá para dividir.
  def razao(valor, base)
    valor.nil? || base.nil? || !base.positive? ? nil : valor / base
  end

  def preco(plano)
    plano['preco_total'].blank? ? nil : BigDecimal(plano['preco_total'].to_s)
  end

  def despesas_medicas(plano)
    Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf::Rotulos.despesas_medicas(plano)
  end

  private_class_method :indice, :pontos_do_preco, :pontos_da_cobertura, :pontos_da_eficiencia, :desconto_da_maior, :razao,
                       :preco, :despesas_medicas
end

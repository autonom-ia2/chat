# Célula da planilha exportada (#682). Texto que começa com =, +, -, @, %, |, tab ou CR pode ser lido como fórmula.
# No CSV não há outro jeito de avisar: ganha um apóstrofo na frente, a mesma regra do CSVSafe. No Excel o texto sai
# intacto: a célula já vai como texto (inlineStr) e leva o estilo quotePrefix, que o Excel mostra sem o apóstrofo e não
# recalcula nem quando a pessoa edita a célula. Número fica como está.
module Autonomia::Prospecting::Export::Cell
  FORMULA_STARTS = ['=', '+', '-', '@', '%', '|', "\t", "\r"].freeze

  module_function

  def formula_start?(value)
    value.is_a?(String) && value.start_with?(*FORMULA_STARTS)
  end

  def safe(value)
    return value if value.nil? || value.is_a?(Numeric)

    text = value.to_s
    formula_start?(text) ? "'#{text}" : text
  end
end

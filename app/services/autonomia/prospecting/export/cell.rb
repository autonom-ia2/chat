# Célula da planilha exportada (#682). Texto que começa com =, +, -, @, %, |, tab ou CR ganha um apóstrofo na frente,
# para a planilha não o ler como fórmula. É a mesma regra do CSVSafe, aplicada uma vez só, antes de escolher o formato:
# o CSV e o Excel saem com a mesma célula. Número fica como está.
module Autonomia::Prospecting::Export::Cell
  FORMULA_STARTS = ['=', '+', '-', '@', '%', '|', "\t", "\r"].freeze

  module_function

  def safe(value)
    return value if value.nil? || value.is_a?(Numeric)

    text = value.to_s
    text.start_with?(*FORMULA_STARTS) ? "'#{text}" : text
  end
end

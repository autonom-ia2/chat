# "Trazer minha lista" (#2896): a coluna da planilha que diz quem já é cliente. Marca quem tem um destes valores, sem
# diferença de maiúscula nem de acento; qualquer outro valor (ou a célula vazia) não marca ninguém.
module ContactImports::Trazer::Cliente
  SIM = (ContactImports::AttributeValue::TRUE_VALUES + %w[sim s x cliente]).uniq.freeze

  module_function

  def marca?(valor)
    SIM.include?(I18n.transliterate(valor.to_s.strip).downcase)
  end
end

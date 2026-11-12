# A frase para a pessoa corrigir a receita (`autonomia.automacao.receita.*`), comum à Receita e aos validadores dela
# (#2608).
module Autonomia::Automacao::Receita::Frase
  private

  def texto(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", **valores)
end

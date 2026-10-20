# #1920: o que as IAs que escrevem frase (critério da etapa e "quando usar" do funil) precisam saber do funil e do
# negócio para escrever a fronteira certa. A tela manda o que está no formulário (`formulario`), que vale por cima do
# salvo: o funil pode ainda não existir, ou ter o tipo e o "quando usar" mudados e não salvos.
module Crm::Ai::ContextoDoFunil
  BOOLEANO = ActiveModel::Type::Boolean.new

  def self.funil(pipeline, formulario = {})
    formulario = formulario.to_h.stringify_keys
    vende = formulario.key?('counts_as_sale') ? BOOLEANO.cast(formulario['counts_as_sale']) != false : pipeline.counts_as_sale?
    quando = formulario.key?('when_to_use') ? formulario['when_to_use'] : pipeline.when_to_use
    { name: pipeline.name, kind: vende ? 'sell' : 'serve', when_to_use: quando.to_s.strip.first(Crm::Pipeline::MAX_WHEN_TO_USE).presence }.compact
  end

  # O ramo que a conta informou no cadastro e o nicho que o super admin escolheu para ela (nunca o padrão da
  # instalação, que vale para contas de qualquer ramo). nil quando não há nenhum dos dois.
  def self.negocio(account)
    escolha = Autonomia::Agents::Nicho.for(account)
    nicho = [escolha.nicho, escolha.perfil].compact.join('/') unless escolha.padrao? || escolha.nicho == Autonomia::Agents::Nicho::GERAL
    { industry: account.custom_attributes.to_h['industry'].presence, niche: nicho }.compact.presence
  end

  # O `funil` que o controller permitiu (o tipo e o "quando usar" do formulário), em texto e no tamanho do campo.
  def self.do_formulario(funil)
    return {} if funil.blank?

    funil.to_h.stringify_keys.slice('counts_as_sale', 'when_to_use').transform_values { |valor| valor.to_s.first(Crm::Pipeline::MAX_WHEN_TO_USE) }
  end
end

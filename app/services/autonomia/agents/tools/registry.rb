# Catálogo das ferramentas NATIVAS disponíveis na instalação (#312).
#
# Nativa é declarada em código, não no banco: quem decide que ela existe somos nós; o dono da conta
# só decide se liga (`agent.config['native_tool_slugs']`). Isso é deliberado — a ferramenta nativa
# carrega credencial e assinatura, então a superfície precisa ser fechada.
module Autonomia::Agents::Tools::Registry
  # Ordem estável: entra no prompt nesta ordem quando o agente liga várias.
  TOOLS = [
    # Ordem é a da jornada: o que a corretora cota, cotar, e o que o contrato diz.
    Autonomia::Agents::Tools::Native::InsuranceCapabilities,
    # UMA ferramenta para os onze ramos. Havia duas — uma só de auto, com os campos digitados à
    # mão, e outra para o resto —, e a separação custava caro: o comparativo em PDF e o registro da
    # seguradora que recusou a credencial da corretora ficavam de fora dos outros dez, e nenhum dos
    # dois é de auto. Auto é um ramo com UM comportamento extra, o bônus de renovação.
    Autonomia::Agents::Tools::Native::InsuranceQuote,
    Autonomia::Agents::Tools::Native::InsuranceGeneralConditions
  ].freeze

  module_function

  def all
    TOOLS
  end

  def find(slug)
    TOOLS.find { |tool| tool.slug == slug.to_s }
  end

  def slugs
    TOOLS.map(&:slug)
  end

  # Ferramentas realmente utilizáveis por este agente: ligadas na config E disponíveis (o gate
  # `available_for?` evita oferecer no prompt algo que vai falhar por falta de configuração).
  def for_agent(agent)
    enabled = Array(agent.native_tool_slugs).map(&:to_s)
    return [] if enabled.empty?

    enabled.filter_map { |slug| find(slug) }.uniq.select { |tool| tool.available_for?(agent) }
  end
end

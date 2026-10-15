# #1548 (passo 2) — variante do modelo de funil por tipo de conta: a própria lista de categorias das etapas
# (`metadata.category`, #1515). A chave é a camada do pacote da F1 (Autonomia::Segmentos::Pacotes, #1550), que já
# respeita AUTONOMIA_PACOTES_ENABLED: palavras e lógica ligam juntas. Conta sem camada fica com o modelo de hoje.
#
# Saúde e benefícios: no Atendimento, "Esperando a operadora" (E3) é andamento e não pausa o prazo.
# A lista é uma só para o painel e o servidor: SOURCE, que o funil.js também importa.
class Crm::PipelineStages::TemplateVariant
  SOURCE = Rails.root.join('app/javascript/dashboard/routes/dashboard/crm/components/funil/variantes.json')
  CATEGORIES = JSON.parse(SOURCE.read).transform_values { |modelos| modelos.transform_values(&:freeze).freeze }.freeze

  # Categoria da etapa E<position> do modelo na variante da conta; nil quando a conta não tem variante desse modelo.
  def self.category_for(account:, template:, position:)
    index = Integer(position.to_s, 10, exception: false)
    return unless index&.positive?

    categories_for(account, template.to_s)&.[](index - 1)
  end

  # Da camada mais específica (seguros/<tipo>) para a mais geral (seguros).
  def self.categories_for(account, template)
    camada = Autonomia::Segmentos::Pacotes.camadas(account).reverse.find { |item| CATEGORIES.dig(item, template) }
    CATEGORIES.dig(camada, template) if camada
  end
  private_class_method :categories_for
end

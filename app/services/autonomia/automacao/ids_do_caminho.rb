# #2471: o id escrito direto no caminho de uma ação (não um `$valor`) aponta para um registro desta conta. Sem esta
# conferência, o id errado (o Guia que inventa um, a receita copiada de outra conta) só falha ao rodar: o endpoint
# responde 404 e o passo termina com erro permanente no histórico. Não há vazamento: o motor chama pelo caminho da conta
# da execução, com o token de quem ligou. A tela não erra aqui, porque o ChoiceSelect só busca na conta.
#
# O recurso do parâmetro é o segmento antes dele, com o `crm/` ou o `autonomia/` da rota
# (`crm/pipelines/:pipeline_id/stages` → crm/pipelines). Só os recursos da lista são conferidos; o resto do caminho
# segue a régua de sempre. O spec cobra que toda estrutura da conta (AcoesPermitidas::ESTRUTURA) que aparecer no caminho
# de uma ação permitida entre aqui: os lotes da #2660 trouxeram time, caixa, políticas, agente de IA, decisor, agenda e
# central de ajuda.
module Autonomia::Automacao::IdsDoCaminho
  # O recurso na rota → a lista da conta onde o id tem de estar (e a chave do nome em autonomia.automacao.receita.recurso).
  RECURSOS = {
    'labels' => :labels,
    'custom_attribute_definitions' => :custom_attribute_definitions,
    'crm/pipelines' => :crm_pipelines,
    'crm/stages' => :crm_pipeline_stages,
    'crm/booking_pages' => :crm_agent_booking_profiles,
    'teams' => :teams,
    'inboxes' => :inboxes,
    'sla_policies' => :sla_policies,
    'assignment_policies' => :assignment_policies,
    'agent_capacity_policies' => :agent_capacity_policies,
    'portals' => :portals,
    'categories' => :categories,
    'autonomia/agents' => :autonomia_agents,
    'autonomia/decisores' => :autonomia_decisores
  }.freeze
  # A lista que não é associação da conta, ou que a rota procura por outra coluna (o portal vai pelo slug), com a
  # mesma busca do controller.
  BUSCAS = {
    autonomia_agents: ->(conta, id) { ::Autonomia::Agents::Agent.kept.where(account: conta).exists?(id: id) },
    autonomia_decisores: ->(conta, id) { ::Autonomia::Decisor.where(account: conta).exists?(id: id) },
    portals: ->(conta, id) { conta.portals.exists?(slug: id.to_s) }
  }.freeze
  PREFIXOS = %w[crm autonomia].freeze

  module_function

  # [[lista da conta, id], ...] dos ids literais do caminho que a conta não tem. Sem conta (o catálogo), nada a conferir.
  def de_fora(acao, caminho, conta)
    return [] if conta.nil?

    valores = caminho.to_h
    recursos(acao).filter_map do |parametro, lista|
      id = valores[parametro]
      next if id.blank? || id.is_a?(Hash) || existe?(conta, lista, id)

      [lista, id]
    end
  end

  def existe?(conta, lista, id)
    busca = BUSCAS[lista]
    busca ? busca.call(conta, id) : conta.public_send(lista).exists?(id: id)
  end

  # { 'pipeline_id' => :crm_pipelines, ... }: os parâmetros da rota cujo recurso está na lista.
  def recursos(acao)
    segmentos = acao.to_s.split(' ', 2).last.to_s.split('/')
    prefixo = PREFIXOS.include?(segmentos.first) ? "#{segmentos.first}/" : ''
    segmentos.each_with_index.filter_map do |segmento, indice|
      next unless segmento.start_with?(':') && indice.positive?

      lista = RECURSOS["#{prefixo}#{segmentos[indice - 1]}"]
      [segmento.delete_prefix(':'), lista] if lista
    end.to_h
  end
end

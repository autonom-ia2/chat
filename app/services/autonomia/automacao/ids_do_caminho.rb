# #2471: o id escrito direto no caminho de uma ação (não um `$valor`) aponta para um registro desta conta. Sem esta
# conferência, o id errado (o Guia que inventa um, a receita copiada de outra conta) só falha ao rodar: o endpoint
# responde 404 e o passo termina com erro permanente no histórico. Não há vazamento: o motor chama pelo caminho da conta
# da execução, com o token de quem ligou. A tela não erra aqui, porque o ChoiceSelect só busca na conta.
#
# O recurso do parâmetro é o segmento antes dele, com o `crm/` da rota (`crm/pipelines/:pipeline_id/stages` →
# crm/pipelines). Só os recursos da lista são conferidos; o resto do caminho segue a régua de sempre.
#
# Caixa de entrada, time e agente não estão na lista: nenhuma ação permitida (AcoesPermitidas) os tem no caminho, só no
# corpo (a atribuição leva `team_id` e `assignee_id`). O spec cobra que a estrutura que entrar num caminho entre aqui.
module Autonomia::Automacao::IdsDoCaminho
  # O recurso na rota → a lista da conta onde o id tem de estar (e a chave do nome em autonomia.automacao.receita.recurso).
  RECURSOS = {
    'labels' => :labels,
    'custom_attribute_definitions' => :custom_attribute_definitions,
    'crm/pipelines' => :crm_pipelines,
    'crm/stages' => :crm_pipeline_stages
  }.freeze
  CRM = 'crm'.freeze

  module_function

  # [[lista da conta, id], ...] dos ids literais do caminho que a conta não tem. Sem conta (o catálogo), nada a conferir.
  def de_fora(acao, caminho, conta)
    return [] if conta.nil?

    valores = caminho.to_h
    recursos(acao).filter_map do |parametro, lista|
      id = valores[parametro]
      next if id.blank? || id.is_a?(Hash) || conta.public_send(lista).exists?(id: id)

      [lista, id]
    end
  end

  # { 'pipeline_id' => :crm_pipelines, ... }: os parâmetros da rota cujo recurso está na lista.
  def recursos(acao)
    segmentos = acao.to_s.split(' ', 2).last.to_s.split('/')
    prefixo = segmentos.first == CRM ? "#{CRM}/" : ''
    segmentos.each_with_index.filter_map do |segmento, indice|
      next unless segmento.start_with?(':') && indice.positive?

      lista = RECURSOS["#{prefixo}#{segmentos[indice - 1]}"]
      [segmento.delete_prefix(':'), lista] if lista
    end.to_h
  end
end

# QUEM MUDOU AS LISTAS DE UM AGENTE QUE JÁ ATENDE (#2976). A mudança das perguntas e dos documentos de um agente pronto
# por ramo vale na mensagem seguinte do cliente e não passa pelas versões da instrução (a `Edicao` grava só a marca, sem
# tocar no `updated_at`). Por isso fica aqui a trilha: quem, quando, em qual agente, quais listas e quantos itens
# valendo antes e depois. No molde do `Autonomia::Agents::SoftDelete`, na mesma transação da gravação.
#
# Só metadados: o texto dos itens é do negócio do dono e não entra no registro. O rascunho não é registrado: ele ainda
# não atende ninguém.
module Autonomia::Agents::ModelosDeRamo::RegistroDaMudanca
  EVENTO = 'autonomia.agent.listas_do_ramo_mudadas'.freeze
  COMENTARIO = 'Listas do agente pronto por ramo'.freeze

  module_function

  # `listas`: os nomes das listas que o pedido trouxe (perguntas, documentos). `antes` e `depois`: a marca.
  def gravar!(agente:, autor:, antes:, depois:, listas:)
    Audited.audit_class.create!(
      auditable: agente, associated: agente.account, user: autor, action: 'update', comment: COMENTARIO,
      audited_changes: { event: EVENTO, account_id: agente.account_id, agent_id: agente.id, actor_id: autor&.id,
                         listas: listas.index_with { |lista| { antes: valendo(antes, lista), depois: valendo(depois, lista) } } }
    )
  end

  # Quantos itens da lista o agente segue (os tirados ficam guardados, fora do agente).
  def valendo(marca, lista)
    Autonomia::Agents::ModelosDeRamo::Marca.itens(marca, lista).count { |item| !item['tirada'] }
  end
end

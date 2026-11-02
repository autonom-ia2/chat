# #2489 — o andaime e o cartão acompanham a instrução no "Mudar conversando" (Fase 2). A tabela de destino
# (AjustePorLista) manda o Construtor reescrever os dois quando a instrução muda; esta é a garantia no código.
# A instrução mudou por um pedido que não é só de estilo e um dos dois voltou com o texto de antes: o item da instrução
# não foi atendido, e a correção que já existe roda (uma vez); ainda igual, segue o não atendido de sempre.
# Só igualdade de texto, antes e depois: o código nunca lê o que o texto diz (regra do Rodrigo, 20/09/2026).
# Pedido de estilo: o mesmo `pedido` também foi para o tone (pela tabela, "no maximo 2 frases" vai para os dois).
module Autonomia::Agents::Builder::RoteiroDoAjuste
  module_function

  # Sem o roteiro de antes (versão sem o agente), não confere.
  def com_roteiro_conferido(conferencia, antes, depois)
    itens = Array(conferencia['itens'])
    alvo = itens_do_roteiro(itens)
    return conferencia if alvo.empty? || antes.blank? || !roteiro_parado?(antes, depois)

    marcados = itens.map { |item| alvo.include?(item) ? item.merge('atendido' => false, 'roteiro_parado' => true) : item }
    conferencia.merge('itens' => marcados, 'falta' => true)
  end

  def itens_do_roteiro(itens)
    de_estilo = itens.select { |item| item['campo'] == 'tone' }.pluck('pedido')
    itens.select do |item|
      item['campo'] == 'instruction' && item['pedido_pelo_dono'] != false && de_estilo.exclude?(item['pedido'])
    end
  end

  def roteiro_parado?(antes, depois)
    return false if antes['instruction'] == depois['instruction']

    antes['scaffold'] == depois['scaffold'] || antes['human_card'] == depois['human_card']
  end

  # O que a garantia compara: a instrução, o andaime e o cartão. Nunca vai ao dono nem a outro modelo.
  def roteiro(agent)
    { 'instruction' => agent.instruction.to_s, 'scaffold' => agent.scaffold.to_s, 'human_card' => agent.human_card.to_s }
  end

  # O mesmo, lido da versão de antes do ajuste. {} quando a versão não guarda o agente.
  def roteiro_da_versao(versao)
    agente = versao && versao.metadata.to_h['agente']
    return {} unless agente.is_a?(Hash)

    { 'instruction' => versao.instruction.to_s, 'scaffold' => agente['scaffold'].to_s, 'human_card' => agente['human_card'].to_s }
  end
end

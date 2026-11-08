# Quem a reunião de um card acorda (G32, #2710): as execuções paradas num "esperar até" no próprio card, nos outros
# cards do mesmo contato, no contato e nas conversas dele. A página de agendamento põe a reunião no card aberto do funil
# e, sem ele (o card já ganho), cria outro; quem espera no card ganho lê `contato.tem_reuniao_marcada` e precisa
# acordar com a reunião do card novo. Só acorda o "esperar até" cuja condição lê um dos valores de reunião: a espera
# pela resposta do cliente não é reservada à toa a cada reunião do contato.
module Autonomia::Automacao::EsperaDaReuniao
  VALORES = %w[card.tem_reuniao_marcada contato.tem_reuniao_marcada].freeze

  module_function

  # O passo em que a execução espera lê um valor de reunião? O caminho fica em `{"$valor": "..."}` dentro da condição.
  def le_reuniao?(execucao)
    passo = ::Autonomia::Automacao::Roteiro.new(execucao.versao.receita).passo(execucao.cursor)
    caminhos = caminhos_da(passo.to_h['condicao'])
    VALORES.any? { |valor| caminhos.include?(valor) }
  end

  def caminhos_da(trecho)
    case trecho
    when Hash then trecho.flat_map { |chave, valor| chave == '$valor' ? [valor] : caminhos_da(valor) }
    when Array then trecho.flat_map { |item| caminhos_da(item) }
    else []
    end
  end

  # `card_id`: o id do card da reunião (o gate do emissor só tem o id). Sempre preso à conta.
  def de(account_id, card_id)
    card = ::Crm::Card.where(id: card_id, account_id: account_id)
    contato = card.where.not(contact_id: nil).select(:contact_id)
    execucoes = ::Autonomia::Automacao::Execucao.where(account_id: account_id, estado: 'esperando')
    execucoes.where(alvo_type: 'Crm::Card', alvo_id: card.select(:id))
             .or(execucoes.where(alvo_type: 'Crm::Card', alvo_id: ::Crm::Card.where(account_id: account_id, contact_id: contato).select(:id)))
             .or(execucoes.where(alvo_type: 'Contact', alvo_id: contato))
             .or(execucoes.where(alvo_type: 'Conversation', alvo_id: ::Conversation.where(account_id: account_id, contact_id: contato).select(:id)))
  end
end

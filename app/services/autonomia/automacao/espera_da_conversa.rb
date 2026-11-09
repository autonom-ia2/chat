# Quem espera pela conversa: a execução dela e a do card cuja conversa principal é ela (G11: a resposta do cliente
# acorda o card na hora, em vez de no fim do prazo). Com `contato_id`, também quem espera por ele em outra conversa, no
# card dele ou no próprio contato (#2680: o e-mail abre outra conversa). Sempre preso à conta.
module Autonomia::Automacao::EsperaDaConversa
  module_function

  def de(account, conversa_ids, contato_id = nil)
    execucoes = ::Autonomia::Automacao::Execucao.where(account_id: account.id, estado: 'esperando')
    conversas = contato_id ? ::Conversation.where(account_id: account.id, contact_id: contato_id).select(:id) : conversa_ids
    cards = ::Crm::Card.where(account_id: account.id, conversation_id: conversas)
    cards = cards.or(::Crm::Card.where(account_id: account.id, contact_id: contato_id)) if contato_id
    pelas_conversas = execucoes.where(alvo_type: 'Conversation', alvo_id: conversas)
                               .or(execucoes.where(alvo_type: 'Crm::Card', alvo_id: cards.select(:id)))
    contato_id ? pelas_conversas.or(execucoes.where(alvo_type: 'Contact', alvo_id: contato_id)) : pelas_conversas
  end
end

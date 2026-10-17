# Memória das IAs (#1601): só confere a flag e enfileira; o trabalho é dos jobs de Crm::Memoria. A troca de
# responsável e a conversa resolvida mexem na tarefa de retomar (Crm::Memoria::ConversaJob).
#
# Na mensagem mudada, só reage ao que muda a autoria ou a entrega: texto, nota privada, remetente, marcas do canal
# (`content_attributes`, inclusive a mensagem apagada), `source_id` e o envio que falhou. O recibo de entregue e lido
# (status sent -> delivered -> read) não enfileira nada, nem a mudança só "de pele" das marcas do canal (reação, recibo,
# prévia de link, voto, mensagem escondida...: CHAVES_DE_PELE, a mesma lista do #1702b; quando o
# ConversaCanal::AtualizacaoDaPele estiver na main, ela passa a ser a fonte).
class Crm::MemoriaListener < BaseListener
  CAMPOS = %w[content private sender_type sender_id source_id message_type].freeze
  # `deleted_by_contact_at` NÃO é pele: o cliente retirou o que disse (#1709).
  CHAVES_DE_PELE = %w[reactions read_receipt_sent_at link_preview played_at poll_votes event_responses c2y_hidden
                      view_once_resolved_by].freeze
  FALHOU = 'failed'.freeze

  def message_created(event)
    message = event.data[:message]
    return if atividade_escondida?(message)
    return unless Crm::Memoria.ativa?(message&.conversation)

    Crm::Memoria::OrigemJob.perform_later(message.id)
  end

  def message_updated(event)
    message = event.data[:message]
    return unless relevante?(event.data[:previous_changes])
    return unless Crm::Memoria.ativa?(message&.conversation)

    Crm::Memoria::OrigemJob.perform_later(message.id)
  end

  def assignee_changed(event)
    enfileirar_da_conversa(event, 'dono')
  end

  def conversation_resolved(event)
    enfileirar_da_conversa(event, 'resolvida')
  end

  private

  def enfileirar_da_conversa(event, evento)
    conversation = event.data[:conversation]
    return unless Crm::Memoria.ativa?(conversation)

    Crm::Memoria::ConversaJob.perform_later(conversation.id, evento)
  end

  def atividade_escondida?(message)
    message.present? && message.activity? && message.content_attributes.to_h['c2y_hidden'].present?
  end

  def relevante?(mudancas)
    mudancas = mudancas.to_h.stringify_keys
    return true if mudancas.keys.intersect?(CAMPOS)
    return true if marcas_mudaram?(mudancas['content_attributes'])

    Array(mudancas['status']).last.to_s == FALHOU
  end

  # As marcas do canal mudaram além da pele (forwarded, external_echo, deleted, crm_follow_up_id...).
  def marcas_mudaram?(mudanca)
    return false unless mudanca.is_a?(Array) && mudanca.size == 2

    antes, depois = mudanca.map { |valor| hash_de(valor) }
    chaves = (antes.keys | depois.keys).reject { |chave| antes[chave] == depois[chave] }
    (chaves - CHAVES_DE_PELE).any?
  end

  # `content_attributes` é JSON gravado como texto dentro do json: pode chegar como String.
  def hash_de(valor)
    valor = JSON.parse(valor) if valor.is_a?(String)
    valor.is_a?(Hash) ? valor.stringify_keys : {}
  rescue JSON::ParserError
    {}
  end
end

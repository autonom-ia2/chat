# "ME TIREM DA CÓPIA" DE CARONA NA AVALIAÇÃO DE CARD (#1828). O pedido para sair da cópia é percebido mesmo sem
# cadência de follow-up: a avaliação de card que já roda a cada mensagem (Crm::Ai::StageClassifier e a conjunta) ganha,
# só com a flag `email_autoria`, o campo `saida_da_copia` no schema e a instrução no FIM do prompt (o cache e o schema
# de quem não tem a flag ficam iguais). Nenhuma chamada nova; quem decide se foi um pedido é o modelo.
#
# O modelo devolve endereços; o código só aceita o autor da mensagem NOVA (o e-mail recebido mais recente do card), e só
# se ele não é o cliente nem a equipe (Crm::Email::Autoria: outra pessoa), e grava com
# Crm::Email::Destinatarios.registrar_saida!. Texto injetado por um participante não tira outra pessoa da cópia, e o
# cliente nunca sai.
module Crm::Email::SaidaDaCopia
  CAMPO = 'saida_da_copia'.freeze
  INSTRUCAO = <<~TEXTO.squish.freeze
    SAÍDA DA CÓPIA ("saida_da_copia"): só quando a mensagem MAIS RECENTE começa com "[E-mail de ..., endereço que não
    é do cliente" e quem a escreveu pede para não receber mais cópia destes e-mails ou para sair da conversa, ponha o
    endereço do aviso, exatamente como está. O cliente nunca entra nesta lista, nem quem só pede outra coisa. Sem
    pedido assim, [].
  TEXTO

  module_function

  def com_saida(schema)
    corpo = schema[:schema]
    schema.merge(
      schema: corpo.merge(properties: corpo[:properties].merge(CAMPO.to_sym => { type: 'array', items: { type: 'string' } }),
                          required: [*corpo[:required], CAMPO])
    )
  end

  # Os endereços que o modelo apontou e que de fato escreveram (não são o cliente) num e-mail recente do card.
  def aplicar!(card, enderecos)
    pedidos = Array(enderecos).map { |endereco| endereco.to_s.strip.downcase }.compact_blank.uniq
    return if pedidos.empty?

    autoria = Crm::Email::Autoria.new(card.account)
    return unless autoria.ligada?

    message = mais_recente(card)
    return if message.nil?

    resultado = autoria.de(message)
    Crm::Email::Destinatarios.registrar_saida!(message.conversation, resultado.remetente) if pediu?(resultado, pedidos)
  rescue StandardError => e
    # A avaliação já foi aplicada; só a saída da cópia se perde, com o erro no rastreador.
    ChatwootExceptionTracker.new(e, account: card.account).capture_exception
  end

  # Quem escreveu é outra pessoa (não o cliente, nem a equipe, nem resposta automática) e o modelo apontou o endereço.
  def pediu?(resultado, pedidos)
    resultado.present? && resultado.tipo == Crm::Email::Autoria::OUTRA_PESSOA && pedidos.include?(resultado.remetente)
  end

  # A mensagem nova: o e-mail recebido mais recente das conversas do card.
  def mais_recente(card)
    conversas = [card.conversation_id, *card.card_conversations.pluck(:conversation_id)].compact.uniq
    Message.where(account_id: card.account_id, conversation_id: conversas, message_type: :incoming, content_type: :incoming_email)
           .includes(:conversation).reorder(id: :desc).first
  end
end

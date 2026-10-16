# Uma PESSOA da equipe escreveu ao cliente sem se atribuir (#1669). Pela decisão de 13/10 a IA segue na conversa, com o
# robô no nome, até alguém clicar em "Atribuir a mim". Duas coisas mudam, só com a Fase 2 ligada:
#
# (a) No histórico que vai ao modelo, a mensagem da pessoa chega MARCADA como dela, num item de papel `user` com a
#     moldura "[Ana, da equipe, escreveu ao cliente. ...]". Antes ela ia como `assistant`, e a IA lia o que a Ana
#     escreveu como se fosse dela. Por que `user` e não `assistant` com prefixo: o item `assistant` é a voz do próprio
#     modelo, e um prefixo ali é o exemplo mais forte de como ele "fala" — é o caminho mais curto para ele imitar a
#     marca na resposta. No `user` a marca é dado de entrada, como o contexto e os documentos (PromptParts), e o que
#     o modelo escreveu continua sem marca nenhuma. `developer` daria ao texto da pessoa autoridade de instrução.
# (b) Se a pessoa respondeu publicamente DEPOIS da mensagem do cliente que o turno vai responder, a IA não responde
#     aquela mensagem (silêncio `pessoa_respondeu`). A IA não sai da conversa: a próxima mensagem do cliente, mais
#     nova que a resposta da pessoa, volta a ser dela.
#
# A marca nunca sai ao cliente: `sem_marca` corta, da resposta, a linha (ou o começo de linha) que imita a moldura.
# Fora da Fase 2 nada aqui é aplicado: o histórico e a entrega ficam como na main.
module Autonomia::Agents::Operate::PessoaDaEquipe
  # O pedaço fixo da moldura, o que identifica a marca na resposta. A moldura é nossa, não texto do cliente.
  CHAVE_DA_MARCA = ', da equipe, escreveu ao cliente'.freeze
  NOME_PADRAO = 'Uma pessoa'.freeze
  NOME_MAX = 60

  module_function

  def aplica?(conversation)
    ::Autonomia::Agents::Fase2.ligada?(conversation&.account)
  end

  # Mensagem pública que uma pessoa da equipe mandou ao cliente: não robô, não sistema, não nota privada. Regra de
  # automação e disparo de campanha gravados em nome dela não contam, como no `Message#human_response?`.
  def da_pessoa?(message)
    message.outgoing? && !message.private? && message.sender_type == 'User' &&
      message.content_attributes.to_h['automation_rule_id'].blank? && !campanha?(message)
  end

  def campanha?(message)
    extras = message.additional_attributes.to_h
    extras['campaign_id'].present? || extras['whatsapp_api_campaign_id'].present?
  end

  # O item do histórico para o Answerer. A mensagem da pessoa vai marcada; as demais, como sempre.
  def item_do_historico(message)
    return { role: 'user', content: marcar(message) } if da_pessoa?(message)

    { role: message.incoming? ? 'user' : 'assistant', content: message.content.to_s }
  end

  def marcar(message)
    texto = message.content.to_s
    return texto if texto.blank?

    "[#{nome(message.sender)}#{CHAVE_DA_MARCA}. Não foi o cliente nem você.]\n#{texto}"
  end

  # O nome que o painel mostra (`available_name`), numa linha, sem os colchetes que fechariam a moldura.
  def nome(user)
    limpo = user&.available_name.to_s.split.join(' ').delete('[]').first(NOME_MAX)
    limpo.presence || NOME_PADRAO
  end

  # Uma pessoa respondeu publicamente depois da mensagem `message_id` do cliente? Estado fresco: consulta o banco.
  def respondeu_depois?(conversation, message_id)
    return false if message_id.blank? || !aplica?(conversation)

    conversation.messages.chat.outgoing.where(sender_type: 'User').where('id > ?', message_id.to_i)
                .any? { |message| da_pessoa?(message) }
  end

  # A resposta do modelo sem a moldura, caso ele a tenha imitado. Corta o começo de cada linha que abre com `[` e
  # traz a chave da marca antes do primeiro `]`; a linha que fica vazia sai.
  def sem_marca(reply)
    return reply if reply.blank? || reply.exclude?(CHAVE_DA_MARCA)

    reply.lines.filter_map { |linha| linha_sem_marca(linha) }.join.strip
  end

  def linha_sem_marca(linha)
    inicio = linha.lstrip
    fim = inicio.index(']')
    return linha unless inicio.start_with?('[') && fim && inicio[0..fim].include?(CHAVE_DA_MARCA)

    resto = inicio[(fim + 1)..].lstrip
    resto.presence
  end
end

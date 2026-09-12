# A ENTREGA QUE JÁ ESTÁ NA CONVERSA — a MENSAGEM que carrega o token dela (rodada 3 da entrega 8).
#
# O publicador carimba cada mensagem com `autonomia_async_token`, a identidade da entrega derivada
# do CONTEÚDO (`ToolRun#delivery_token`): é por ele que um retry não duplica. Quem precisa saber se
# algo já chegou ao cliente pergunta AQUI, e não ao handle da execução — o handle é a intenção de
# quem publicou, a mensagem é o fato. A proposta individual (entrega 8) avançava `enviadas` antes de
# publicar, e uma publicação que voltava `blocked` deixava o arquivo contado como enviado sem
# existir (Codex, rodada 2, P2).
#
# O `LIKE` é só a peneira barata (não há índice para a chave dentro do JSON); quem decide é a
# comparação exata do atributo.
module Autonomia::Agents::Tools::EntregaPublicada
  CHAVE = 'autonomia_async_token'.freeze

  module_function

  # -> a mensagem desta conversa que já carrega o token, ou nil.
  def para(conversation, token)
    return nil if conversation.blank? || token.blank?

    conversation.messages.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .detect { |message| message.content_attributes.to_h[CHAVE].to_s == token }
  end

  def existe?(conversation, token)
    para(conversation, token).present?
  end
end

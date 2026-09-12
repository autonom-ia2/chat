# A ENTREGA QUE JÁ ESTÁ NA CONVERSA — a MENSAGEM que carrega o token dela (entrega 8).
#
# O publicador carimba cada mensagem com `autonomia_async_token`, a identidade da entrega derivada
# do CONTEÚDO (`ToolRun#delivery_token`): é por ele que um retry não duplica. Quem precisa saber se
# algo já chegou ao cliente pergunta AQUI, e não ao handle da execução — o handle é a intenção de
# quem publicou, a mensagem é o fato, e os dois divergem sempre que a publicação volta `blocked`
# depois de o handle já ter avançado.
#
# Duas perguntas, uma identidade só. `token_de` é a IDENTIDADE que uma entrega TERÁ como mensagem, e
# mora aqui porque quem pergunta "já chegou?" precisa montá-la ANTES de a mensagem existir: a
# ferramenta a grava no handle na passada que emite a entrega, e o fecho a procura na conversa
# depois. Duas definições da mesma identidade — uma no publicador, outra em quem pergunta — seriam
# duas que divergem no dia em que a forma da entrega mudar, e a pergunta passaria a ser sobre uma
# mensagem que nunca existiu.
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

  # A identidade que ESTA entrega tem (ou terá) como mensagem desta execução. A entrega de ARQUIVO
  # responde por si (`EntregaDeArquivo#identidade`: a mesma como anexo e como link de reserva, para
  # que um retry não publique o arquivo por cima do link); o texto responde por si mesmo, aparado
  # como o publicador o apara antes de postar. nil sem execução — sem `execution_key` não há token,
  # e quem não tem token não afirma nada.
  def token_de(run, entrega)
    return nil if run.blank?

    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
    run.delivery_token(arquivo ? arquivo.identidade : entrega.to_s.strip)
  end

  # -> esta entrega JÁ É uma mensagem na conversa? É a pergunta do FATO, e a única que o fecho pode
  # fazer: o handle diz o que se tentou entregar, não o que chegou.
  def publicada?(conversation, token)
    para(conversation, token).present?
  end
end

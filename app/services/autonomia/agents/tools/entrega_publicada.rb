# A ENTREGA QUE JÁ ESTÁ NA CONVERSA — a MENSAGEM que carrega o token dela (entrega 8).
#
# O publicador carimba cada mensagem com `autonomia_async_token`, a identidade da entrega derivada
# do CONTEÚDO (`ToolRun#delivery_token`): é por ele que um retry não duplica, e é por ele que se
# pergunta "esta entrega já é uma mensagem?".
#
# ISTO NÃO É A PERGUNTA "O CLIENTE JÁ RECEBEU?" — essa é `Tools::EntregaAceita`, o registro do
# ACEITE. A mensagem só nasce quando a publicação é IMEDIATA; enquanto a cadeia de entrega
# humanizada do turno está em curso (até 90 s), a publicação volta `deferred` e a mensagem ainda
# não existe. Quem decide o fecho pela ausência da mensagem nessa janela cala para um cliente que
# vai receber os preços segundos depois — foi o defeito da rodada 3 da entrega 8a. Aqui a pergunta
# é outra, e tem um consumidor só: a IDEMPOTÊNCIA do fecho (`Tools::Encerramento`), que precisa
# saber se AQUELA frase já está na conversa antes de escolher outra.
#
# Duas perguntas, uma identidade só. `token_de` é a IDENTIDADE que uma entrega TERÁ como mensagem, e
# mora aqui porque quem pergunta precisa montá-la ANTES de a mensagem existir: a ferramenta a grava
# no handle na passada que EMITE a entrega, o publicador a carimba na mensagem quando ela nasce, e o
# registro do ACEITE (`Tools::EntregaAceita`) guarda a das entregas que o publicador assumiu. Duas
# definições da mesma identidade — uma no publicador, outra em quem pergunta — seriam duas que
# divergem no dia em que a forma da entrega mudar, e a pergunta passaria a ser sobre uma mensagem
# que nunca existiu.
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
  # responde por si (`EntregaDeArquivo#identidade`: derivada só da URL, a mesma como anexo e como o
  # link de reserva que versões anteriores publicavam); o texto responde por si mesmo, aparado
  # como o publicador o apara antes de postar. nil sem execução — sem `execution_key` não há token,
  # e quem não tem token não afirma nada.
  def token_de(run, entrega)
    return nil if run.blank?

    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
    run.delivery_token(arquivo ? arquivo.identidade : entrega.to_s.strip)
  end

  # -> esta entrega já é uma mensagem na conversa E SEM PENDÊNCIA DE ENVIO conhecida?
  #
  # MENSAGEM NO BANCO NÃO É MENSAGEM ENTREGUE. O publicador marca (`Tools::PendenciaDeEnvio`) a
  # mensagem cujo `SendReplyJob` não entrou na fila: ela existe, o cliente não a recebeu, e quem a
  # encontrar pelo token deve TENTAR DE NOVO em vez de dar a entrega por feita. É o que
  # `AsyncPublisher#retomar` faz — achar a mensagem pelo token e reemitir o envio, sob o lock, sem
  # duplicar a mensagem.
  #
  # Por isso a pendência responde "ainda não": quem pergunta é o fecho idempotente
  # (`Tools::Encerramento#fecho_publicado?`), e publicar de novo nesse estado é exatamente o certo
  # — a dedupe por conteúdo do publicador encontra a mesma mensagem e retoma o envio dela. Dizer
  # "já saiu" deixaria o fecho no banco e o cliente sem nenhuma palavra.
  #
  # `para` NÃO filtra a pendência, de propósito: quem quer a MENSAGEM (o publicador, para retomá-la)
  # precisa dela justamente quando ela está pendente.
  def publicada?(conversation, token)
    mensagem = para(conversation, token)
    mensagem.present? && !::Autonomia::Agents::Tools::PendenciaDeEnvio.pendente?(mensagem)
  end
end

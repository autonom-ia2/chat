# A RETOMADA DO ENVIO PENDENTE (rodada 9 da entrega 11, dois P2 do Codex).
#
# A mensagem do publicador está no banco e o `SendReplyJob` dela não entrou na fila — a marca
# `PendenciaDeEnvio` diz isso. Quem a resolve são dois caminhos, e os dois passam por aqui:
#
# 1. A TENTATIVA SEGUINTE do publicador (a reemissão da mesma entrega, o retry): acha a mensagem pelo
#    token SOB O LOCK da conversa e chama `retomar` ALI, sem soltar o lock. Até a rodada 8 a
#    retomada corria FORA do lock: duas tentativas concorrentes liam a marca uma depois da outra,
#    cada uma sob o seu lock, e as duas reenfileiravam — dois `SendReplyJob`, o documento duas
#    vezes. Com a retomada inteira (reler, decidir, enfileirar, limpar) dentro do lock, a segunda
#    entra depois de a primeira limpar a marca e não acha pendência.
#
# 2. O VARREDOR (`ReapStaleRunsJob`, a cada 10 min): a única recuperação DURÁVEL. Sem ele, a marca
#    dependia de alguém reemitir a entrega — e ninguém reemite: o `AsyncRunJob#apply` publica e
#    encerra, `comparativo_enviado` impede nova emissão do PDF, o `AsyncPublishJob` para em
#    `blocked`, e o Redis voltar não dispara nada. `recuperar` trava a conversa da mensagem, RELÊ a
#    mensagem sob o lock, reconfere a autorização (a mesma do publicador, `AutorizacaoDaExecucao`) e
#    decide: reenfileira e limpa; ou abandona (limpa a marca e registra o motivo, fechado) quando a
#    autorização caiu, o canal já confirmou (`source_id`), a mensagem é nota privada, ou a própria
#    FERRAMENTA já não entregaria aquilo (rodada 4 da entrega 8, P1 do Codex: a proposta de uma
#    cotação que foi refeita depois do pedido). A mensagem estar no painel não é ter chegado ao
#    cliente — reenfileirar o `SendReplyJob` dela é entregar o arquivo agora —, e por isso a
#    pergunta à ferramenta vale aqui como vale no publicador: o que identifica a entrega é o TOKEN
#    que a mensagem carrega (`EntregaPublicada::CHAVE`), e é a ferramenta que o resolve.
#
# `reenviar` é a mecânica comum: o `SendReplyJob` é no-op para mensagem já enviada
# (`Base::SendOnChannelService#invalid_message?` → `source_id.present?`) e para nota privada. Se o
# enfileiramento não entra (o Redis continua fora, ou `perform_later` devolve `false` sem exceção —
# um callback de enqueue barrou, ou o adapter levantou `EnqueueError`), a falha é explícita: código
# fechado no log e a marca gravada (ou mantida) para o varredor. A marca só sai quando o job ENTRA.
#
# O ENFILEIRAMENTO DENTRO DO LOCK É IMEDIATO: `ActiveJob::Base.enqueue_after_transaction_commit` é
# `:never` nesta instalação (`load_defaults 7.0`, sem a chave em `config/`; lido em
# `activejob 7.2.3.1`, `EnqueueAfterTransactionCommit#raw_enqueue`). Se um dia for `:default`, o
# adapter do Sidekiq adia o enqueue para depois do commit e marca `successfully_enqueued` ANTES de ele
# acontecer — `reenviar` diria "entrou" sem ter entrado. `async_publisher_spec` guarda o fato pelo
# comportamento: o job está na fila ainda dentro do lock.
#
# RESSALVA (Codex, rodada 8; #393): se o Redis ACEITA o enfileiramento e perde a resposta na mesma
# chamada, o adapter levanta, e este reenvio põe um SEGUNDO `SendReplyJob`. O `SendReplyJob` não
# serializa o envio da mesma mensagem; com as threads da fila, o cliente pode receber o documento
# duas vezes. Custo escolhido contra a alternativa — o cliente sem arquivo e sem link.
class Autonomia::Agents::Tools::RetomadaDeEnvio
  include ::Autonomia::Agents::Tools::AutorizacaoDaExecucao

  Pendencia = ::Autonomia::Agents::Tools::PendenciaDeEnvio

  def initialize(run:)
    @run = run
  end

  # A mensagem que o token achou É a entrega — a menos que carregue a PENDÊNCIA de envio. Chamada SOB
  # O LOCK da conversa, com a mensagem lida sob ele. -> true quando a entrega está resolvida (sem
  # pendência, ou o envio entrou); false quando a pendência fica.
  def retomar(mensagem)
    return true unless Pendencia.pendente?(mensagem)

    Rails.logger.warn("[autonomia][tool][async] envio pendente encontrado run=#{@run.id} message=#{mensagem.id}")
    reenviar(mensagem)
  end

  # -> true quando o `SendReplyJob` ENTROU na fila (e a marca saiu); false quando não (a marca fica
  # gravada, com o código fechado no log).
  def reenviar(mensagem)
    causa = enfileirar(mensagem)
    return envio_pendente!(mensagem, causa) if causa

    Pendencia.limpar(mensagem, contexto: contexto) if Pendencia.marcada?(mensagem)
    Rails.logger.warn("[autonomia][tool][async] envio reenfileirado run=#{@run.id} message=#{mensagem.id}")
    true
  end

  # A RECUPERAÇÃO DURÁVEL, pelo varredor: tudo sob o lock da conversa da mensagem — reler, reconferir
  # a autorização, decidir, enfileirar, limpar. -> true quando não resta pendência (enviado, abandonado
  # ou já resolvido por outro), false quando ela fica.
  def recuperar(mensagem)
    conversation = mensagem.conversation
    return abandonar(mensagem, 'sem_conversa') if conversation.nil?

    conversation.with_lock { decidir(conversation, Message.find_by(id: mensagem.id)) }
  end

  private

  # A mensagem RELIDA sob o lock. Apagada, ou sem a marca (outra tentativa já resolveu: o job dela
  # está a caminho, ou o canal confirmou): nada a fazer. Com a marca, quem decide é a mesma
  # autorização do publicador — o que não vai ser enviado por este caminho é abandonado com motivo, e o
  # resto segue pelo MESMO `retomar` da tentativa seguinte (o log conta a mesma história dos dois lados).
  def decidir(conversation, mensagem)
    return true if mensagem.nil? || !Pendencia.marcada?(mensagem)
    return abandonar(mensagem, 'canal_confirmou') if mensagem.source_id.present?
    return abandonar(mensagem, 'nota_privada') if mensagem.private?

    autorizado = autorizacao(conversation, token: token_de(mensagem))
    return abandonar(mensagem, autorizado.to_s) if recusada?(autorizado)

    retomar(mensagem)
  end

  # O TOKEN DA ENTREGA que esta mensagem carrega — o carimbo que o publicador pôs nela. É por ele que
  # a FERRAMENTA reconhece o que é seu (`Native::Base#entrega_do_token`) e diz se aquilo ainda pode
  # chegar ao cliente. Mensagem sem token (ou de quem não reconhece o token) não é recusada por aqui:
  # vale o resto da autorização, como antes.
  def token_de(mensagem)
    mensagem.content_attributes.to_h[::Autonomia::Agents::Tools::EntregaPublicada::CHAVE]
  end

  # A marca sai (senão o varredor a acharia a cada 10 min) e o motivo, fechado, vai ao log.
  def abandonar(mensagem, motivo)
    Pendencia.abandonar(mensagem, motivo: motivo, contexto: contexto)
    true
  end

  # -> nil quando o `SendReplyJob` ENTROU na fila; a causa quando não: a classe da exceção, ou o
  # código `enqueue_recusado` para o `false` sem exceção de `perform_later`.
  def enfileirar(mensagem)
    ::SendReplyJob.perform_later(mensagem.id) ? nil : 'enqueue_recusado'
  rescue StandardError => e
    e.class.name
  end

  # A pendência fica gravada na mensagem COM a execução que a publicou (é por ela que o varredor
  # reconfere a autorização); a falha da própria marca não troca este resultado — é registrada por ela.
  def envio_pendente!(mensagem, causa)
    Pendencia.marcar(mensagem, run_id: @run.id, contexto: contexto)
    Rails.logger.warn("[autonomia][tool][async] publicacao incompleta run=#{@run.id} message=#{mensagem.id} " \
                      "motivo=mensagem_sem_envio causa=#{causa}")
    false
  end

  def contexto
    "run=#{@run.id}"
  end
end

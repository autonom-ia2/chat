# PUBLICADOR da entrega assíncrona (#313).
#
# Separado do `Operate::Responder` de propósito. O Responder tem lógica de POSSE DO TURNO
# (`still_eligible?`, `already_replied?`) que aqui não se aplica: isto não é resposta a uma mensagem,
# é a entrega de algo que o cliente pediu e está esperando. Mas AUTORIZAÇÃO continua valendo inteira
# — quem publica sem checar kill-switch da conta, estado do agente e allowlist de piloto acaba
# falando com cliente real a partir de um agente que já foi desligado.
#
# SEIS decisões que este arquivo carrega:
#
# 1. NUNCA carimba `autonomia_reply_to_message_id`. O `already_replied?` do Responder é um regex
#    sobre QUALQUER outgoing do bot com aquele id: uma entrega assíncrona que o herdasse faria o
#    Responder achar que o turno já respondeu e DESCARTAR a resposta real, em silêncio.
#
# 2. Com humano na conversa, publica como NOTA PRIVADA. O corretor recebe a cotação e decide como
#    apresentar; o cliente não recebe o robô falando por cima de quem já está atendendo.
#
# 3. ESPERA a cadeia de entrega humanizada drenar. Aquela cadeia pode durar até 90s encadeando até 5
#    mensagens; publicar no meio dela entrega "encontrei 3 opções" antes de "deixa eu consultar", e
#    ainda quebra a janela de mídia do turno seguinte (um outgoing entre duas incoming muda o que
#    `current_turn_incoming` considera turno atual).
#
# 4. A ENTREGA DE ARQUIVO (entrega 11) é publicada como ANEXO: o publicador baixa a URL e GRAVA o
#    arquivo no armazenamento na hora de publicar (`EntregaDeArquivo#gravar`, pelo `SafeFetch`: o
#    endereço conectado conferido, teto de tamanho, prazo do corpo com teto por leitura e assinatura
#    de PDF), FORA do lock da conversa, e anexa o blob gravado (pelo `signed_id`) pelo
#    `Messages::MessageBuilder` — o mesmo caminho do agente humano que manda um arquivo. Quando o
#    download OU a gravação falham, sai o texto de reserva com o link, como saía antes, com o motivo
#    no log: a falha do arquivo não apaga a entrega, e nunca é silenciosa. A identidade é a mesma nos
#    dois caminhos, então um retry não publica o arquivo por cima do link.
#
# 5. A AUTORIZAÇÃO É RECONFERIDA SOB O LOCK, sem cache, imediatamente antes de criar a mensagem
#    (rodada 7, 11/09/2026). Entre a conferência do começo e a mensagem há um download e uma gravação
#    (segundos), e nesse intervalo a execução pode ser supersedida, o agente desligado, a allowlist
#    mudar ou a conversa trocar de caixa. Publicar com a conferência velha era o buraco do primeiro
#    parágrafo por outra porta. O que foi recusado aqui sai registrado (`publicacao recusada`), e o
#    blob que ficou sem dono vai para a limpeza.
#
# 6. A EXCEÇÃO DEPOIS DO COMMIT É RECONCILIADA PELO ENVIO, não pela mensagem (rodada 7). A mensagem
#    no banco não é entrega: o cliente só recebe quando o `send_reply` da `Message` enfileira o
#    `SendReplyJob`, e esse callback vem DEPOIS do despacho de eventos, que fala com o Redis. Se a
#    exceção veio antes dele, o envio não foi disparado: o publicador o dispara (o `SendReplyJob` é
#    no-op para mensagem já enviada) ou, se nem isso entra na fila, devolve `blocked` com código
#    fechado. `published` no papel, com o cliente sem arquivo e sem link, é o que este arquivo nunca
#    pode dizer.
class Autonomia::Agents::Tools::AsyncPublisher
  # Motivos de não-publicação, devolvidos a quem chamou (o job decide se re-agenda ou encerra).
  Result = Struct.new(:status, :message, keyword_init: true) do
    def published? = status == :published
    def deferred? = status == :deferred
    def blocked? = status == :blocked
    def skipped? = status == :skipped
  end

  # O que vira UMA mensagem na conversa: o texto, o token de idempotência (a identidade da entrega)
  # e, na entrega de arquivo, o anexo — o `signed_id` do blob já gravado no armazenamento.
  Corpo = Struct.new(:texto, :token, :anexo, keyword_init: true)

  # O que a publicação sob o lock pode dizer além de "criei esta mensagem": a mensagem já estava lá
  # (retry), ou a autorização caiu no caminho (os dois motivos fechados que vão ao log).
  DUPLICADA = :duplicate
  RECUSAS = %i[execucao_morta vinculo_mudou].freeze

  def initialize(run:)
    @run = run
  end

  # -> Result. NUNCA levanta: falhar em publicar não pode derrubar a execução inteira.
  # `entrega` é um texto ou uma entrega de arquivo (o objeto, ou a forma serializada que atravessa o
  # job); a autorização e a espera pela cadeia são as mesmas para as duas. O QUE NÃO É NENHUMA DAS
  # DUAS (um Hash de outra forma, uma forma de arquivo que a validação recusa) é descartado AQUI,
  # registrado: o encerramento (`closing_deliveries`) não passa pelo `Progress`, e sem esta guarda
  # o `to_s` do Hash chegava ao cliente como mensagem, literal (rodada 2 de revisão, 11/09/2026).
  def publish(entrega, wait_for_chain: true)
    arquivo = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega)
    sem_conteudo = nada_a_publicar(entrega, arquivo)
    return sem_conteudo if sem_conteudo

    conversation = authorized_conversation
    return Result.new(status: :blocked) if conversation.blank?
    return Result.new(status: :deferred) if wait_for_chain && humanized_chain_open?(conversation)

    entregar(conversation, arquivo, entrega.to_s.strip)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] publish failed run=#{@run.id} #{e.class}")
    Result.new(status: :blocked)
  end

  # Publica SEM esperar a cadeia de chunks drenar. Último recurso, usado quando o teto de adiamentos
  # estourou: mensagem fora de ordem é ruim, mensagem que nunca chega é pior — e uma cadeia que não
  # termina (o cliente escreveu no meio e ela foi abortada) travaria a entrega para sempre.
  def publish!(entrega)
    publish(entrega, wait_for_chain: false)
  end

  private

  # -> Result quando não há o que publicar, nil quando há. Texto em branco sai calado (é o mesmo
  # `skipped` de sempre); o que não é texto nem arquivo sai REGISTRADO — é uma entrega que alguém
  # montou errado, e o silêncio esconderia isso.
  def nada_a_publicar(entrega, arquivo)
    return if arquivo
    return descartar(entrega) unless entrega.is_a?(String)

    Result.new(status: :skipped) if entrega.strip.blank?
  end

  # Só a CLASSE vai ao log: o conteúdo de uma entrega que não é entrega pode ser qualquer coisa.
  def descartar(entrega)
    Rails.logger.warn("[autonomia][tool][async] entrega descartada run=#{@run.id}: não é texto nem arquivo (#{entrega.class.name})")
    Result.new(status: :skipped)
  end

  # A conversa em que esta execução AINDA pode publicar, ou nil. É a conferência de ENTRADA: barra
  # cedo o que já não pode publicar, antes de baixar arquivo nenhum. A conferência que VALE para a
  # mensagem é a de `publicar_sob_lock`, refeita sob o lock, sem cache.
  #
  # Execução morta (supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da
  # conta) não publica: uma entrega adiada de uma cotação que o cliente já corrigiu sairia até 90s
  # depois, e ele receberia dois preços conflitantes. NÃO basta exigir `running?` — a entrega final
  # legítima é publicada e a linha fechada logo em seguida, então uma republicação adiada
  # encontraria a linha já `done`.
  def authorized_conversation
    return if @run.reload.dead?

    conversation = @run.conversation
    return if conversation.blank?
    return unless same_binding?(vinculo_autorizado(conversation.reload))

    conversation
  end

  # O vínculo autorizado AGORA, lido do banco a cada chamada — nunca memoizado: quem memoizava
  # publicava, depois de segundos de download, com a autorização de antes dele (Codex, rodada 7).
  def vinculo_autorizado(conversation)
    ::Autonomia::Agents::Operate.authorized_agent_inbox(conversation)
  end

  # O vínculo autorizado agora é o MESMO que aceitou a execução? A conversa pode ter mudado de caixa
  # (ou o vínculo ter sido recriado) entre o disparo e a entrega — nesse caso a cotação não é mais
  # deste agente. Execução antiga sem `agent_inbox_id` gravado aceita qualquer vínculo autorizado.
  def same_binding?(agent_inbox)
    return false if agent_inbox.blank?

    @run.agent_inbox_id.blank? || @run.agent_inbox_id == agent_inbox.id
  end

  # Há uma cadeia de entrega humanizada em curso para o turno que originou esta execução? A cadeia
  # carimba `autonomia_chunk_token` = "<reply_to>:<índice>"; se o ÚLTIMO índice esperado ainda não
  # apareceu, ela não terminou.
  def humanized_chain_open?(conversation)
    expected = @run.expected_chunks.to_i
    # `expected == 1` TAMBÉM espera: um pedaço único não foi postado, está agendado com atraso de até
    # 15s. Só `0` (caminho clássico e de voz, que postam de forma síncrona antes do despacho) dispensa.
    return false if expected < 1 || @run.origin_message_id.blank?

    !chunk_posted?(conversation, expected - 1)
  end

  def chunk_posted?(conversation, index)
    token = "#{@run.origin_message_id}:#{index}"
    conversation.messages.outgoing.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .any? { |message| message.content_attributes.to_h['autonomia_chunk_token'].to_s == token }
  end

  # Publica sob lock da conversa, com idempotência pelo CONTEÚDO da entrega — retry do Sidekiq, ou
  # consulta que reemite a mesma lista, encontra a mensagem já postada e não duplica. O bloco do lock
  # só delega (`publicar_sob_lock`): um `return` dentro dele mudaria o destino da transação.
  #
  # A leitura da sequência e o avanço ficam DENTRO do lock: dois publicadores concorrentes (duas
  # entregas parciais adiadas com o mesmo atraso, duas threads da fila) liam o mesmo número, e o
  # segundo via a posição ocupada, descartava o texto e ainda devolvia sucesso — a segunda cotação
  # sumia sem ninguém notar.
  #
  # `corpo.token` é a identidade da entrega (o texto, por padrão; a URL, na entrega de arquivo).
  #
  # O QUE LEVANTA DEPOIS DO COMMIT (um `after_commit` da mensagem que ESTA chamada criou e que FICOU
  # no banco) é reconciliado pelo envio (`reconciliar`); o que levanta antes, ou com a transação
  # desfeita (`persisted?` volta a ser falso no rollback), sobe para quem chamou decidir — a reserva,
  # na entrega de arquivo; `blocked`, no fim. Só a mensagem desta chamada é reconciliada: uma mensagem
  # achada pelo token poderia ser de outro publicador, com um envio dele a caminho.
  def post(conversation, corpo)
    vigia = ::Autonomia::Agents::Tools::VigiaDeEnvio.new
    publicado = nil
    vigia.observar { conversation.with_lock { publicado = publicar_sob_lock(conversation, corpo) } }
    resultado(publicado)
  rescue StandardError => e
    raise unless publicado.is_a?(Message) && publicado.persisted?

    reconciliar(publicado, vigia, e)
  end

  # -> a mensagem criada, `DUPLICADA`, ou o motivo da recusa. A AUTORIZAÇÃO É RECONFERIDA AQUI, sob o
  # lock e sem cache: `dead?` relido do banco e o vínculo recalculado (`authorized_agent_inbox` sobre a
  # conversa que o lock acabou de recarregar — conta habilitada, agente ligado e ativo, allowlist,
  # mesma caixa). É esta conferência, não a da entrada, que autoriza a mensagem.
  def publicar_sob_lock(conversation, corpo)
    return :execucao_morta if @run.reload.dead?

    agent_inbox = vinculo_autorizado(conversation)
    return :vinculo_mudou unless same_binding?(agent_inbox)

    sequence = @run.sequence
    return DUPLICADA if delivery_posted?(conversation, corpo.token)

    mensagem = build_message!(conversation, agent_inbox, sequence, corpo)
    # Só avança quando uma mensagem NOVA entrou: como a idempotência é pelo conteúdo, o duplicado
    # não ocupa posição nenhuma, e avançar nele faria o contador mentir sobre quantas mensagens a
    # execução publicou.
    @run.advance_sequence!(sequence)
    mensagem
  end

  def resultado(publicado)
    return Result.new(status: :published, message: publicado) if publicado.is_a?(Message)
    return Result.new(status: :published) if publicado == DUPLICADA

    Rails.logger.warn("[autonomia][tool][async] publicacao recusada run=#{@run.id} motivo=#{publicado}")
    Result.new(status: :blocked)
  end

  # A mensagem está no banco e a exceção veio de um `after_commit` dela. O que decide o resultado é se
  # o ENVIO AO CANAL foi disparado: a nota privada não vai ao canal; `source_id` só existe depois de
  # o canal responder; e o vigia viu (ou não) o `SendReplyJob` desta mensagem entrar na fila. Sem
  # nenhum dos três, o `send_reply` não chegou a rodar — a exceção veio antes dele.
  def reconciliar(mensagem, vigia, erro)
    Rails.logger.warn("[autonomia][tool][async] publicacao levantou depois do commit run=#{@run.id} message=#{mensagem.id} causa=#{erro.class}")
    return Result.new(status: :published) if envio_disparado?(mensagem, vigia)

    reenviar(mensagem)
  end

  def envio_disparado?(mensagem, vigia)
    mensagem.private? || mensagem.source_id.present? || vigia.enfileirou?(mensagem.id)
  end

  # RECUPERAÇÃO idempotente e durável: o `SendReplyJob` é no-op para mensagem já enviada
  # (`Base::SendOnChannelService#invalid_message?` → `source_id.present?`) e para nota privada; e o
  # que garante que não há OUTRO job desta mensagem a caminho é o vigia — o `send_reply` não chegou
  # a enfileirar. Se nem isto entra na fila (o Redis continua fora), a falha é explícita: código
  # fechado no log, `blocked` para quem chamou (ninguém conta a entrega), a mensagem e o anexo ficam.
  def reenviar(mensagem)
    ::SendReplyJob.perform_later(mensagem.id)
    Rails.logger.warn("[autonomia][tool][async] envio reenfileirado run=#{@run.id} message=#{mensagem.id}")
    Result.new(status: :published)
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] publicacao incompleta run=#{@run.id} message=#{mensagem.id} " \
                      "motivo=mensagem_sem_envio causa=#{e.class}")
    Result.new(status: :blocked)
  end

  def entregar(conversation, arquivo, texto)
    return post_arquivo(conversation, arquivo) if arquivo

    post(conversation, Corpo.new(texto: texto, token: @run.delivery_token(texto)))
  end

  # O ARQUIVO BAIXA E É GRAVADO FORA DO LOCK da conversa: é rede, com tetos próprios, e a conversa
  # não pode ficar travada por ele. Gravar ANTES da mensagem é o que põe a falha do armazenamento
  # dentro da mesma fronteira de reserva que a do download: o ActiveStorage subiria o arquivo só no
  # `after_commit` da mensagem, e uma subida que falhasse ali deixaria a legenda no ar com um anexo
  # sem bytes e o token já publicado (rodada 3, 11/09/2026). Quando o download ou a gravação não
  # entregam um PDF, vai a reserva (o texto com o link) com o mesmo token — e o motivo no log, com
  # o código curto e a classe da causa, nunca o texto da resposta nem da exceção.
  #
  # O blob que NÃO virou anexo (o retry que encontrou a mensagem no ar, a publicação que não
  # concluiu, a autorização que caiu no caminho) é apagado EM SEGUNDO PLANO
  # (`EntregaDeArquivo.agendar_limpeza` → `purge_later`): gravado antes da mensagem, ele não tem dono
  # até ela existir. Apagá-lo aqui, na hora, era falar com o armazenamento de novo dentro do
  # `ensure`, e um `delete` que falha (rede) saía do `ensure` por cima do resultado: a entrega que
  # JÁ estava no ar virava `blocked` e "publish failed" no log, e a exceção de uma publicação que
  # levantou era trocada pela do purge (rodada 4, 11/09/2026). E o AGENDAMENTO também fala com o
  # Redis, dentro do mesmo `ensure`: quando ele falha, `agendar_limpeza` registra e não levanta
  # (rodada 5). Só assim o resultado da publicação é o da publicação — nunca uma mensagem a menos
  # nem um log que aponta para a causa errada. O blob leva a MARCA da execução (rodada 7): se o
  # processo morrer entre a gravação e este `ensure`, o varredor (`ReapStaleRunsJob`) o reconhece.
  def post_arquivo(conversation, arquivo)
    token = @run.delivery_token(arquivo.identidade)
    blob = arquivo.gravar(run_id: @run.id)
    anexado = false
    resultado, anexado = publicar_anexo(conversation, arquivo, token, blob)
    resultado
  rescue ::Autonomia::Agents::Tools::EntregaDeArquivo::Indisponivel => e
    Rails.logger.warn("[autonomia][tool][async] arquivo indisponivel run=#{@run.id} motivo=#{e.motivo}" \
                      "#{" causa=#{e.causa}" if e.causa}; vai como link")
    post(conversation, Corpo.new(texto: arquivo.reserva, token: token))
  ensure
    ::Autonomia::Agents::Tools::EntregaDeArquivo.agendar_limpeza(blob, contexto: "run=#{@run.id}") if blob && !anexado
  end

  # -> [Result, o blob ficou com dono?]. O blob tem dono quando a mensagem NOVA saiu com ele, ou quando
  # está anexado a uma mensagem que ficou no banco (a publicação reconciliada depois do commit, com
  # ou sem envio — apagar o blob dela seria a mensagem no ar sem arquivo). O retry que achou a
  # mensagem no ar e a publicação recusada sob o lock não dão dono: o blob vai para a limpeza.
  #
  # A FALHA AO ANEXAR sem mensagem no banco (a transação voltou: anexo inválido, banco), depois de um
  # download e uma gravação bons, cai na RESERVA com o MESMO token, registrada com a classe da causa
  # — nunca a mensagem da exceção (rodada 6, 11/09/2026). Se a reserva também levantar, sobe para o
  # `publish`, que devolve `blocked`, como sempre.
  def publicar_anexo(conversation, arquivo, token, blob)
    resultado = post(conversation, Corpo.new(texto: arquivo.legenda, token: token, anexo: blob.signed_id))
    [resultado, resultado.message.present? || blob.attachments.exists?]
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] anexo falhou run=#{@run.id} causa=#{e.class}; vai como link")
    [post(conversation, Corpo.new(texto: arquivo.reserva, token: token)), false]
  end

  def delivery_posted?(conversation, token)
    conversation.messages.where(sender_type: 'AgentBot')
                .where('content_attributes::text LIKE ?', "%#{token}%")
                .any? { |message| message.content_attributes.to_h['autonomia_async_token'].to_s == token }
  end

  def build_message!(conversation, agent_inbox, sequence, corpo)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: corpo.texto,
        attachments: [corpo.anexo].compact.presence,
        # Com responsável na conversa a entrega vira NOTA PRIVADA: quem fala com o cliente é a
        # pessoa que assumiu, e ela precisa do dado — não do robô por cima dela.
        message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: agent_inbox.agent_bot_id, private: conversation.assignee_id.present?,
        content_attributes: {
          autonomia_agent_id: agent_inbox.agent.id,
          autonomia_async_token: corpo.token,
          autonomia_async_slug: @run.slug,
          autonomia_async_sequence: sequence
        }
      )
    ).perform
  end
end

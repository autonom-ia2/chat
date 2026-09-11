# PUBLICADOR da entrega assíncrona (#313).
#
# Separado do `Operate::Responder` de propósito. O Responder tem lógica de POSSE DO TURNO
# (`still_eligible?`, `already_replied?`) que aqui não se aplica: isto não é resposta a uma mensagem,
# é a entrega de algo que o cliente pediu e está esperando. Mas AUTORIZAÇÃO continua valendo inteira
# — quem publica sem checar kill-switch da conta, estado do agente e allowlist de piloto acaba
# falando com cliente real a partir de um agente que já foi desligado.
#
# TRÊS decisões que este arquivo carrega:
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
#    arquivo no armazenamento na hora de publicar (`EntregaDeArquivo#gravar`, com teto de tamanho,
#    de tempo e assinatura de PDF), FORA do lock da conversa, e anexa o blob gravado (pelo
#    `signed_id`) pelo `Messages::MessageBuilder` — o mesmo caminho do agente humano que manda um
#    arquivo. Quando o download OU a gravação falham, sai o texto de reserva com o link, como saía
#    antes, com o motivo no log: a falha do arquivo não apaga a entrega, e nunca é silenciosa. A
#    identidade é a mesma nos dois caminhos, então um retry não publica o arquivo por cima do link.
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

    entregar(conversation, authorized_inbox(conversation), arquivo, entrega.to_s.strip)
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

  # A conversa em que esta execução AINDA pode publicar, ou nil.
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
    return unless same_binding?(authorized_inbox(conversation))

    conversation
  end

  def authorized_inbox(conversation)
    @authorized_inbox ||= ::Autonomia::Agents::Operate.authorized_agent_inbox(conversation.reload)
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
  # consulta que reemite a mesma lista, encontra a mensagem já postada e não duplica. Sem `return`
  # dentro do bloco (dispararia ROLLBACK e descartaria a mensagem recém-criada), como no operate.
  #
  # A leitura da sequência e o avanço ficam DENTRO do lock: dois
  # publicadores concorrentes (duas entregas parciais adiadas com o mesmo atraso, duas threads da
  # fila) liam o mesmo número, e o segundo via a posição ocupada, descartava o texto e ainda
  # devolvia sucesso — a segunda cotação sumia sem ninguém notar.
  #
  # `corpo.token` é a identidade da entrega (o texto, por padrão; a URL, na entrega de arquivo).
  def post(conversation, agent_inbox, corpo)
    posted = nil
    conversation.with_lock do
      @run.reload
      sequence = @run.sequence
      if delivery_posted?(conversation, corpo.token)
        posted = :duplicate
      else
        posted = build_message!(conversation, agent_inbox, sequence, corpo)
        # Só avança quando uma mensagem NOVA entrou: como a idempotência é pelo conteúdo, o
        # duplicado não ocupa posição nenhuma, e avançar nele faria o contador mentir sobre
        # quantas mensagens a execução publicou.
        @run.advance_sequence!(sequence)
      end
    end
    Result.new(status: :published, message: (posted unless posted == :duplicate))
  end

  def entregar(conversation, agent_inbox, arquivo, texto)
    return post_arquivo(conversation, agent_inbox, arquivo) if arquivo

    post(conversation, agent_inbox, Corpo.new(texto: texto, token: @run.delivery_token(texto)))
  end

  # O ARQUIVO BAIXA E É GRAVADO FORA DO LOCK da conversa: é rede, com tetos próprios, e a conversa
  # não pode ficar travada por ele. Gravar ANTES da mensagem é o que põe a falha do armazenamento
  # dentro da mesma fronteira de reserva que a do download: o ActiveStorage subiria o arquivo só no
  # `after_commit` da mensagem, e uma subida que falhasse ali deixaria a legenda no ar com um anexo
  # sem bytes e o token já publicado (rodada 3, 11/09/2026). Quando o download ou a gravação não
  # entregam um PDF, vai a reserva (o texto com o link) com o mesmo token — e o motivo no log, com
  # o código curto e a classe da causa, nunca o texto da resposta nem da exceção.
  #
  # O blob que NÃO virou anexo (o retry que encontrou a mensagem no ar, ou a publicação que não
  # concluiu) é apagado EM SEGUNDO PLANO (`purge_later`): gravado antes da mensagem, ele não tem
  # dono até ela existir. Apagá-lo aqui, na hora, era falar com o armazenamento de novo dentro do
  # `ensure`, e um `delete` que falha (rede) saía do `ensure` por cima do resultado: a entrega que
  # JÁ estava no ar virava `blocked` e "publish failed" no log, e a exceção de uma publicação que
  # levantou era trocada pela do purge (rodada 4, 11/09/2026). Com o job, o resultado da
  # publicação é o da publicação; a limpeza tem a fila do Sidekiq (`active_storage_purge`) para
  # tentar de novo, e uma que ainda assim falhe deixa no máximo um arquivo órfão no armazenamento
  # — nunca uma mensagem a menos nem um log que aponta para a causa errada.
  def post_arquivo(conversation, agent_inbox, arquivo)
    token = @run.delivery_token(arquivo.identidade)
    blob = arquivo.gravar
    anexado = false
    resultado = post(conversation, agent_inbox, Corpo.new(texto: arquivo.legenda, token: token, anexo: blob.signed_id))
    anexado = resultado.message.present?
    resultado
  rescue ::Autonomia::Agents::Tools::EntregaDeArquivo::Indisponivel => e
    Rails.logger.warn("[autonomia][tool][async] arquivo indisponivel run=#{@run.id} motivo=#{e.motivo}" \
                      "#{" causa=#{e.causa}" if e.causa}; vai como link")
    post(conversation, agent_inbox, Corpo.new(texto: arquivo.reserva, token: token))
  ensure
    blob.purge_later if blob && !anexado
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

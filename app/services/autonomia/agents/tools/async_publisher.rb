# PUBLICADOR da entrega assíncrona (#313).
#
# Separado do `Operate::Responder` de propósito. O Responder tem lógica de POSSE DO TURNO
# (`still_eligible?`, `already_replied?`) que aqui não se aplica: isto não é resposta a uma mensagem,
# é a entrega de algo que o cliente pediu e está esperando. Mas AUTORIZAÇÃO continua valendo inteira
# — quem publica sem checar kill-switch da conta, estado do agente e allowlist de piloto acaba
# falando com cliente real a partir de um agente que já foi desligado.
#
# SÓ ARQUIVO (PR C). Texto que chegue aqui — de uma execução que atravessou o deploy, de um `AsyncPublishJob`
# enfileirado pela versão anterior, de uma ferramenta que ainda devolva frase — é descartado e registrado: o que
# o cliente lê sobre a cotação é a Lia quem escreve, num turno acionado por evento (`Tools::Evento`). O anexo
# sai SEM legenda.
#
# OITO decisões que este arquivo carrega:
#
# 1. NUNCA carimba `autonomia_reply_to_message_id`. O `already_replied?` do Responder é um regex
#    sobre QUALQUER outgoing do bot com aquele id: uma entrega assíncrona que o herdasse faria o
#    Responder achar que o turno já respondeu e DESCARTAR a resposta real, em silêncio.
#
# 2. Com humano na conversa, publica como NOTA PRIVADA. O corretor recebe a cotação e decide como
#    apresentar; o cliente não recebe o robô falando por cima de quem já está atendendo.
#
# 3. ESPERA a cadeia de entrega humanizada drenar. Aquela cadeia pode durar até 90s encadeando até 5
#    mensagens; publicar no meio dela entrega o arquivo antes de "deixa eu consultar", e
#    ainda quebra a janela de mídia do turno seguinte (um outgoing entre duas incoming muda o que
#    `current_turn_incoming` considera turno atual).
#
# 4. A ENTREGA DE ARQUIVO (entrega 11) é publicada como ANEXO: o publicador baixa a URL e GRAVA o
#    arquivo no armazenamento na hora de publicar (`EntregaDeArquivo#gravar`, pelo `SafeFetch`: o
#    endereço conectado conferido, teto de tamanho, prazo do corpo com teto por leitura e assinatura
#    de PDF), FORA do lock da conversa, e anexa o blob gravado (pelo `signed_id`) pelo
#    `Messages::MessageBuilder` — o mesmo caminho do agente humano que manda um arquivo. Quando o
#    download OU a gravação OU o anexo falham, NADA é publicado e o resultado é `blocked`, com o
#    motivo no log (`sem_arquivo`); o link do portal não vai no lugar desde a fatia 1 do PDF rápido
#    (13/09/2026). A exceção é a mensagem com o mesmo token que já está na conversa: ela responde por
#    esta entrega (`retomar`).
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
#
# 7. A PENDÊNCIA DE ENVIO FICA GRAVADA NA PRÓPRIA MENSAGEM (rodada 8, 11/09/2026):
#    `content_attributes['autonomia_envio_pendente'] = true` (`PendenciaDeEnvio`, uma escrita atômica),
#    com a execução que a publicou, quando nem a recuperação pôs o `SendReplyJob` na fila. Sem a marca,
#    a tentativa seguinte achava o token e dizia `published` sem olhar a mensagem — o cliente sem
#    arquivo e sem link, contado como entregue. Token encontrado só quer dizer entregue quando a
#    mensagem não carrega pendência conhecida: com a marca (sem `source_id`, e não privada) a tentativa
#    seguinte reenfileira, e a marca só sai quando o job ENTRA.
#
# 8. A RETOMADA DA PENDÊNCIA ACONTECE INTEIRA SOB O LOCK DA CONVERSA, e tem um recuperador durável
#    (rodada 9, 11/09/2026; `RetomadaDeEnvio`). Reler a mensagem, decidir, enfileirar e limpar a marca
#    dentro do `with_lock`: duas tentativas concorrentes que achavam a mesma pendência e retomavam FORA
#    do lock enfileiravam dois `SendReplyJob` — o documento duas vezes. E a marca que ninguém reemitia
#    (o job encerra, a cotação não pede outro PDF para a mensagem que já está no banco, o Redis voltar não
#    dispara nada) ficava
#    para sempre: o `ReapStaleRunsJob` a acha a cada 10 min e a resolve pelo mesmo caminho, com a
#    mesma autorização (`AutorizacaoDaExecucao`) reconferida sob o lock.
class Autonomia::Agents::Tools::AsyncPublisher
  include ::Autonomia::Agents::Tools::AutorizacaoDaExecucao
  include Arquivos

  # Motivos de não-publicação, devolvidos a quem chamou (o job decide se re-agenda ou encerra).
  # `adiada` só vem com `deferred`: a forma serializada que quem adia deve pôr nos argumentos do
  # `AsyncPublishJob` — o `ArquivoGravado`, sem a URL do portal.
  Result = Struct.new(:status, :message, :adiada, keyword_init: true) do
    def published? = status == :published
    def deferred? = status == :deferred
    def blocked? = status == :blocked
    def skipped? = status == :skipped

    # O PUBLICADOR ASSUMIU ESTA ENTREGA? Imediata ou adiada. É o que o contador da linha
    # (`record_delivery!`) e o registro do aceite (`Tools::EntregaAceita`) contam, e é a pergunta que o
    # encerramento faz por entrega. A adiada ainda depende do `AsyncPublishJob`, que pode recusá-la
    # depois (autorização, banco); desde a rodada 2 da fatia 1 do PDF rápido o arquivo já está baixado e
    # gravado quando ela volta adiada.
    def aceita? = published? || deferred?
  end

  # O que vira UMA mensagem na conversa: o token de idempotência (a identidade da entrega) e o anexo — o
  # `signed_id` do blob já gravado no armazenamento. Sem anexo, o corpo só pergunta pela mensagem que já existe.
  Corpo = Struct.new(:token, :anexo, keyword_init: true)

  def initialize(run:)
    @run = run
  end

  # -> Result. NUNCA levanta: falhar em publicar não pode derrubar a execução inteira.
  # `entrega` é uma entrega de arquivo (`EntregaDeArquivo`, com a URL de onde baixar) ou um arquivo já
  # gravado (`ArquivoGravado`, a forma que atravessa o adiamento). O QUE NÃO É NENHUMA DELAS — texto,
  # inclusive o de uma execução ou de um job adiado da versão anterior à PR C, um Hash de outra forma, uma
  # forma que a validação recusa — é descartado AQUI, registrado, e nada chega ao cliente.
  #
  # A ENTREGA DE ARQUIVO É BAIXADA E GRAVADA ANTES DE A PUBLICAÇÃO SER ADIADA (`publicar_arquivo`,
  # rodada 2 da fatia 1 do PDF rápido): quem chama sabe, no mesmo resultado, se o arquivo existe.
  #
  # `wait_for_chain` espera a cadeia humanizada do turno; o `AsyncPublishJob` o desliga no teto da `AsyncConfig`.
  def publish(entrega, wait_for_chain: true)
    forma = forma_de(entrega)
    return forma if forma.is_a?(Result)

    conversation = authorized_conversation
    return recusar_na_entrada(forma) if conversation.blank?
    return publicar_arquivo(conversation, forma, wait_for_chain) if forma.is_a?(::Autonomia::Agents::Tools::EntregaDeArquivo)
    return adiar(forma) if wait_for_chain && ::Autonomia::Agents::Tools::CadeiaDoTurno.aberta?(@run, conversation)

    publicar_gravado(conversation, forma)
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

  # -> a forma que se publica (`EntregaDeArquivo` ou `ArquivoGravado` desta execução), ou o `Result` de quando
  # não há o que publicar: o que não é arquivo sai REGISTRADO.
  def forma_de(entrega)
    forma = ::Autonomia::Agents::Tools::EntregaDeArquivo.de(entrega) || ::Autonomia::Agents::Tools::ArquivoGravado.de(entrega)
    return descartar(entrega) if forma.nil?
    return descartar(entrega) if forma.is_a?(::Autonomia::Agents::Tools::ArquivoGravado) && !forma.valida_para?(@run)

    forma
  end

  # Só a CLASSE vai ao log: o conteúdo de uma entrega que não é arquivo pode ser qualquer coisa — inclusive
  # uma frase pronta de uma versão anterior, que não sai mais.
  def descartar(entrega)
    Rails.logger.warn("[autonomia][tool][async] entrega descartada run=#{@run.id}: o motor só publica arquivo (#{entrega.class.name})")
    Result.new(status: :skipped)
  end

  # `deferred`, com a forma que o `AsyncPublishJob` deve carregar.
  def adiar(forma)
    Result.new(status: :deferred, adiada: forma.to_h)
  end

  # A conversa em que esta execução AINDA pode publicar, ou nil. É a conferência de ENTRADA: barra
  # cedo o que já não pode publicar, antes de baixar arquivo nenhum. A conferência que VALE para a
  # mensagem é a de `publicar_sob_lock`, refeita sob o lock, sem cache.
  #
  # Execução morta (supersedida por um pedido novo, descartada com o turno, ou barrada pelo gate da
  # conta) não publica: uma entrega adiada de uma cotação que o cliente já corrigiu sairia até 90s
  # depois, e ele receberia dois resultados conflitantes. NÃO basta exigir `running?` — a entrega final
  # legítima é publicada e a linha fechada logo em seguida, então uma republicação adiada
  # encontraria a linha já `done`.
  def authorized_conversation
    conversation = @run.conversation
    return if conversation.blank?
    return if recusada?(autorizacao(conversation.reload))

    conversation
  end

  # Há uma cadeia de entrega humanizada em curso para o turno que originou esta execução? A pergunta mora em
  # `Tools::CadeiaDoTurno`, que o turno de evento também faz.
  def humanized_chain_open?(conversation)
    ::Autonomia::Agents::Tools::CadeiaDoTurno.aberta?(@run, conversation)
  end

  # Publica sob lock da conversa, com idempotência pela IDENTIDADE da entrega — retry do Sidekiq, ou
  # consulta que reemite a mesma entrega, encontra a mensagem já postada e não duplica. O bloco do lock
  # só delega (`publicar_sob_lock`): um `return` dentro dele mudaria o destino da transação.
  #
  # A leitura da sequência e o avanço ficam DENTRO do lock: dois publicadores concorrentes liam o mesmo
  # número, e o segundo via a posição ocupada, descartava a entrega e ainda devolvia sucesso.
  #
  # `corpo.token` é a identidade da entrega (a URL, na entrega de arquivo).
  #
  # O QUE LEVANTA DEPOIS DO COMMIT (um `after_commit` da mensagem que ESTA chamada criou e que FICOU
  # no banco) é reconciliado pelo envio (`reconciliar`); o que levanta antes, ou com a transação
  # desfeita (`persisted?` volta a ser falso no rollback), sobe para quem chamou decidir — `sem_arquivo`,
  # na entrega de arquivo; `blocked`, no fim. Só a mensagem desta chamada é reconciliada: uma mensagem
  # achada pelo token poderia ser de outro publicador, com um envio dele a caminho — a menos que ela
  # carregue a PENDÊNCIA que quem a criou gravou, e essa é retomada AINDA SOB O LOCK (decisões 7 e 8).
  def post(conversation, corpo)
    vigia = ::Autonomia::Agents::Tools::VigiaDeEnvio.new
    publicado = nil
    vigia.observar { conversation.with_lock { publicado = publicar_sob_lock(conversation, corpo) } }
    resultado(publicado)
  rescue StandardError => e
    raise unless publicado.is_a?(Message) && publicado.persisted?

    reconciliar(publicado, vigia, e)
  end

  # -> a mensagem criada, o `Result` da entrega que JÁ estava lá (retry, ou consulta que reemite a
  # mesma entrega — retomada aqui mesmo, sob o lock, decisão 8), ou o motivo da recusa. A AUTORIZAÇÃO É
  # RECONFERIDA AQUI, sob o lock e sem cache (`AutorizacaoDaExecucao`): `dead?` relido do banco e o
  # vínculo recalculado sobre a conversa que o lock acabou de recarregar — conta habilitada, agente
  # ligado e ativo, allowlist, mesma caixa. É esta conferência, não a da entrada, que autoriza a mensagem.
  def publicar_sob_lock(conversation, corpo)
    agent_inbox = autorizacao(conversation)
    return agent_inbox if recusada?(agent_inbox)

    sequence = @run.sequence
    existente = ::Autonomia::Agents::Tools::EntregaPublicada.para(conversation, corpo.token)
    return retomar(existente) if existente
    # O corpo sem anexo é o de `sem_arquivo`: ele só pergunta pela mensagem que já existe.
    return Result.new(status: :blocked) if corpo.anexo.blank?

    mensagem = build_message!(conversation, agent_inbox, sequence, corpo)
    # Só avança quando uma mensagem NOVA entrou: como a idempotência é pela identidade, o duplicado
    # não ocupa posição nenhuma, e avançar nele faria o contador mentir sobre quantas mensagens a
    # execução publicou.
    @run.advance_sequence!(sequence)
    mensagem
  end

  def resultado(publicado)
    return Result.new(status: :published, message: publicado) if publicado.is_a?(Message)
    return publicado if publicado.is_a?(Result)

    Rails.logger.warn("[autonomia][tool][async] publicacao recusada run=#{@run.id} motivo=#{publicado}")
    Result.new(status: :blocked)
  end

  # A mensagem que o token achou É a entrega — a menos que carregue a PENDÊNCIA de envio (decisão 7):
  # aí o que faltou foi o `SendReplyJob`, e é ele que se tenta de novo, AQUI, sob o lock (decisão 8).
  # `published` sem `message`: nenhuma mensagem nova nasceu.
  def retomar(mensagem)
    Result.new(status: retomada.retomar(mensagem) ? :published : :blocked)
  end

  # A mensagem está no banco e a exceção veio de um `after_commit` dela. O que decide o resultado é se
  # o ENVIO AO CANAL foi disparado: a nota privada não vai ao canal; `source_id` só existe depois de
  # o canal responder; e o vigia viu (ou não) o `SendReplyJob` desta mensagem entrar na fila. Sem
  # nenhum dos três, o `send_reply` não chegou a rodar — a exceção veio antes dele.
  def reconciliar(mensagem, vigia, erro)
    Rails.logger.warn("[autonomia][tool][async] publicacao levantou depois do commit run=#{@run.id} message=#{mensagem.id} causa=#{erro.class}")
    return Result.new(status: :published) if envio_disparado?(mensagem, vigia)

    Result.new(status: retomada.reenviar(mensagem) ? :published : :blocked)
  end

  def envio_disparado?(mensagem, vigia)
    mensagem.private? || mensagem.source_id.present? || vigia.enfileirou?(mensagem.id)
  end

  # A mecânica do reenvio e da marca mora em `RetomadaDeEnvio` (rodada 9): é a mesma que o varredor usa,
  # com a mesma autorização. `blocked` quando nem o envio de recuperação entra na fila — ninguém conta
  # a entrega, a mensagem e o anexo ficam, e a pendência fica gravada para o varredor.
  def retomada
    @retomada ||= ::Autonomia::Agents::Tools::RetomadaDeEnvio.new(run: @run)
  end

  # A IDENTIDADE DA ENTREGA VEM DE `Tools::EntregaPublicada`, e não daqui. Ela é a mesma pergunta
  # que o fecho faz ao banco ("esta entrega virou mensagem?"), e uma segunda definição faria quem pergunta
  # procurar por uma mensagem que nunca existiu.
  def token_de(entrega)
    ::Autonomia::Agents::Tools::EntregaPublicada.token_de(@run, entrega)
  end

  # O ANEXO SAI SEM TEXTO (PR C): quem fala junto do arquivo é a Lia, no turno do evento que vem depois dele.
  def build_message!(conversation, agent_inbox, sequence, corpo)
    Messages::MessageBuilder.new(
      nil, conversation,
      ActionController::Parameters.new(
        content: nil,
        attachments: [corpo.anexo],
        # Com responsável na conversa a entrega vira NOTA PRIVADA: quem fala com o cliente é a
        # pessoa que assumiu, e ela precisa do dado — não do robô por cima dela.
        message_type: 'outgoing', sender_type: 'AgentBot',
        sender_id: agent_inbox.agent_bot_id, private: conversation.assignee_id.present?,
        # A CHAVE DO TOKEN VEM DA CONSTANTE, como o valor já vinha (`token_de`). Escrever o literal
        # aqui e ler pela constante em `EntregaPublicada` são DUAS definições da mesma identidade:
        # renomear a constante faria o leitor procurar uma chave que o escritor nunca grava.
        content_attributes: {
          'autonomia_agent_id' => agent_inbox.agent.id,
          ::Autonomia::Agents::Tools::EntregaPublicada::CHAVE => corpo.token,
          'autonomia_async_slug' => @run.slug,
          'autonomia_async_sequence' => sequence
        }
      )
    ).perform
  end
end

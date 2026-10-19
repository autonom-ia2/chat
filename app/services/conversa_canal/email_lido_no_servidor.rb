# Painel -> servidor do cliente (#1870), uma conversa. Quem chama é o ConversaCanal::EmailLidoNoServidorJob, com a
# conexão já aberta e o lock da caixa na mão (ConversaCanal::ConexaoDoEmail); o painel só enfileira
# (ConversaCanal::LidoNoServidorDoEmail).
#
# - Lida: os e-mails recebidos da conversa até o "lido" dela (agent_last_seen_at), a partir do ponto de partida da caixa
#   (ConversaCanal::EmailLidoCaixa; nada anterior a ele), que o servidor ainda não tem como \Seen ganham
#   `UID STORE +FLAGS.SILENT (\Seen)`. E-mail que chegou depois de a pessoa abrir fica não lido lá.
# - O cliente tirou o \Seen lá depois da última leitura daqui (`desmarcado_no_servidor_em`): o painel respeita e não
#   regrava. Só uma leitura nova aqui, depois disso, volta a marcar.
# - Não lida (decisão 2 do Rodrigo): o último e-mail recebido perde o \Seen (`-FLAGS.SILENT`). Do clique ao STORE, o
#   e-mail fica com a marca de "não lida pendente" (ConversaCanal::EmailLido.nao_lida_pendente!): a importação que rodar
#   no meio não conta a passagem para lido dele. A linha só muda depois do STORE ok; a marca sai ao escrever, ao
#   desistir ou sozinha, pelo TTL.
# - UID: o gravado pela importação, se a UIDVALIDITY ainda é a mesma (nil com nil vale). Os que faltam saem de UM
#   `UID SEARCH` (OR de `HEADER Message-ID`), e o Message-ID de cada resultado é conferido por igualdade antes do STORE e
#   antes de gravar o UID: o SEARCH HEADER casa trecho (ConversaCanal::MessageIdsDoServidor). No máximo LIMITE e-mails
#   por conversa. E-mail que não está mais no INBOX (arquivado, apagado) fica como resolvido e não faz o painel abrir
#   outra conexão a cada abertura.
# - O estado é relido na hora do job: se a pessoa marcou não lida e abriu de novo, vale o último.
class ConversaCanal::EmailLidoNoServidor
  PRAZO = 30.days
  LIMITE = 20

  def initialize(conversation:)
    @conversation = conversation
  end

  def sincroniza?
    return @sincroniza if defined?(@sincroniza)

    @sincroniza = ConversaCanal::EmailLido.sincroniza?(@conversation.inbox)
  end

  # Há e-mail lido aqui que o servidor ainda não tem como lido (sem abrir conexão).
  def lido_pendente?
    sincroniza? && a_marcar_como_lidas.any?
  end

  # Mesmo critério do `unread` do Chatwoot para o último recebido (messages.incoming.last).
  def preparar_nao_lida
    return unless sincroniza?

    ultima = @conversation.messages.incoming.last
    ConversaCanal::EmailLido.nao_lida_pendente!(ultima) if ultima
  end

  # O "não lida" do painel falhou antes de agendar: a marca sai (a importação volta a ver a passagem).
  def desfazer_nao_lida
    ultima = @conversation.messages.incoming.last
    ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id) if ultima
  end

  def marcar_lido(imap)
    return unless ligado?

    mensagens = a_marcar_como_lidas
    escrever(imap, mensagens, '+FLAGS.SILENT', seen: true) if mensagens.any?
  end

  def marcar_nao_lida(imap)
    ultima = @conversation.messages.incoming.last
    return if ultima.nil?

    escrever(imap, [ultima], '-FLAGS.SILENT', seen: false) if ligado? && !lida?(ultima)
    # Escrito (ou não há mais o que escrever): a importação volta a ver a passagem. Falha no STORE mantém a marca para a
    # nova tentativa; quem desiste apaga (ConversaCanal::EmailLidoNoServidorJob#desistir).
    ConversaCanal::EmailLido.nao_lida_resolvida!(ultima.id)
  end

  private

  def ligado?
    ConversaCanal::EmailLido.ligado?(@conversation.inbox)
  end

  def recebidas
    @conversation.messages.incoming.where.not(source_id: [nil, ''])
  end

  def lida?(message)
    @conversation.agent_last_seen_at.present? && @conversation.agent_last_seen_at >= message.created_at
  end

  def a_marcar_como_lidas
    lido_em = @conversation.agent_last_seen_at
    return [] if lido_em.blank?

    desde = [PRAZO.ago, ConversaCanal::EmailLidoCaixa.da_caixa(@conversation.inbox).ponto_de_partida].max
    # Resolvidas: já \Seen lá, ou o cliente tirou o \Seen lá depois da última leitura daqui.
    resolvidas = ConversaCanal::EmailLido.where(inbox_id: @conversation.inbox_id)
                                         .where('seen_no_servidor = TRUE OR desmarcado_no_servidor_em > ?', lido_em)
                                         .select(:message_id)
    recebidas.where(created_at: desde..lido_em).where.not(id: resolvidas).reorder(created_at: :desc).limit(LIMITE).to_a
  end

  def escrever(imap, mensagens, acao, seen:)
    validade = ConversaCanal::ConexaoDoEmail.uidvalidity(imap)
    uids = uids_no_servidor(imap, mensagens, validade)
    imap.uid_store(uids.values, acao, [Net::IMAP::SEEN]) if uids.any?
    # Fora do INBOX: sem o que mudar lá. Lida fica como resolvida; na "não lida" a linha fica como estava.
    gravadas = seen ? mensagens : mensagens.select { |message| uids.key?(message.id) }
    ConversaCanal::EmailLido.gravar!(gravadas, seen: seen, uids: uids, uidvalidity: validade)
  end

  # { message.id => uid }: o gravado que vale, mais os achados na busca única, conferidos por igualdade.
  def uids_no_servidor(imap, mensagens, validade)
    linhas = ConversaCanal::EmailLido.where(message_id: mensagens.map(&:id)).index_by(&:message_id)
    conhecidos, faltando = mensagens.partition { |message| linhas[message.id]&.uid_valido?(validade) }
    uids = conhecidos.to_h { |message| [message.id, linhas[message.id].uid] }
    uids.merge(buscar_uids(imap, faltando.select { |message| message.source_id.present? }, validade))
  end

  def buscar_uids(imap, mensagens, validade)
    return {} if mensagens.empty?

    candidatos = Array(imap.uid_search(busca_por_message_id(mensagens.map(&:source_id))))
    por_message_id = ConversaCanal::MessageIdsDoServidor.new(imap: imap, inbox: @conversation.inbox, uidvalidity: validade)
                                                        .de(candidatos).invert
    mensagens.each_with_object({}) do |message, uids|
      uid = por_message_id[message.source_id]
      uids[message.id] = uid if uid
    end
  end

  # OR em notação prefixada: OR HEADER Message-ID a OR HEADER Message-ID b HEADER Message-ID c.
  def busca_por_message_id(message_ids)
    criterios = message_ids.map { |message_id| ['HEADER', 'Message-ID', message_id] }
    criterios.reverse.reduce { |resto, criterio| ['OR', *criterio, *resto] }
  end
end

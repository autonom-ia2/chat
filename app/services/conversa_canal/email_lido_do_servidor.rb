# Servidor do cliente -> painel (#1870). Chamado pela importação de cada minuto (ConversaCanal::LidoNaImportacaoDoEmail),
# na conexão e dentro do lock dela, com o INBOX já selecionado.
#
# - Janela de JANELA (decisão 3 do Rodrigo): só os e-mails que chegaram ao servidor nesse prazo. Leitura feita no
#   servidor depois disso não volta.
# - Custo por minuto: primeiro só UID e FLAGS da janela. O cabeçalho Message-ID é pedido só para UID que ainda não
#   conhecemos (e-mail novo ou UIDVALIDITY nova), com cache por UID (ConversaCanal::MessageIdsDoServidor). Gravação em
#   lote. Não reaproveita o SEARCH da importação: ele cobre 1 dia (`interval`) e esta janela, 2. CONDSTORE
#   (FETCH CHANGEDSINCE com o MODSEQ da caixa) ficou fora desta entrega: pede SELECT (CONDSTORE) na conexão da importação
#   e MODSEQ guardado por caixa; o UID FETCH FLAGS de até LIMITE e-mails da janela é pequeno (sem corpo, sem cabeçalho).
# - Só a PASSAGEM conta, comparada ao último estado gravado (ConversaCanal::EmailLido.passar!, atômica):
#   - não lido -> lido no ÚLTIMO e-mail recebido: a conversa fica lida aqui (decisão 1);
#   - lido -> não lido no ÚLTIMO e-mail recebido (o cliente marcou "não lido" no Gmail/Outlook): a conversa volta a não
#     lida aqui, como o "marcar como não lida" do painel (decisão do Rodrigo, 19/10). Nada volta ao servidor: não há job
#     daqui, e a importação seguinte vê o mesmo estado gravado, sem passagem.
#   Um "marcar não lida" feito aqui e ainda não escrito no servidor não é desfeito: enquanto o e-mail tem a marca de
#   "não lida pendente" (ConversaCanal::EmailLido.nao_lida_pendente?), a passagem para lido dele não muda a conversa.
# - Primeira vez de cada e-mail (ou linha gravada antes do ponto de partida da caixa, que deixa de valer no recomeço):
#   só grava o estado. Exceção (decisão do Rodrigo, 19/10, "confirmo o lido"): e-mail importado depois do ponto de
#   partida (ConversaCanal::EmailLidoCaixa) que já chega lido conta como passagem para lido. Ele chegou não lido e a
#   pessoa leu antes da primeira sincronização; vale também para o acumulado de uma parada da importação, depois do
#   recomeço. Nada anterior ao ponto de partida muda.
class ConversaCanal::EmailLidoDoServidor
  JANELA = 2.days
  LIMITE = Imap::BaseFetchEmailService::MAX_MESSAGES_PER_SYNC
  ESTADO = %w[UID FLAGS].freeze

  def initialize(channel:, imap:)
    @channel = channel
    @imap = imap
  end

  def sincronizar
    @caixa = ConversaCanal::EmailLidoCaixa.sincronizando!(inbox)
    @no_servidor = estados_no_servidor
    return if @no_servidor.empty?

    conhecidas = linhas_por_uid(@no_servidor.keys)
    novas_conhecidas, lidas_na_chegada = identificar(@no_servidor.keys - conhecidas.keys)
    lidas, nao_lidas = passar(conhecidas.merge(novas_conhecidas))
    aplicar(lidas + lidas_na_chegada, nao_lidas)
  end

  private

  def inbox
    @channel.inbox
  end

  def uidvalidity
    return @uidvalidity if defined?(@uidvalidity)

    @uidvalidity = ConversaCanal::ConexaoDoEmail.uidvalidity(@imap)
  end

  # { uid => seen } dos e-mails do INBOX na janela (os mais novos, até LIMITE).
  def estados_no_servidor
    seqs = Array(@imap.search(['SINCE', (Time.zone.today - JANELA).strftime('%d-%b-%Y')])).last(LIMITE)
    return {} if seqs.empty?

    Array(@imap.fetch(seqs, ESTADO)).to_h { |data| [data.attr['UID'], Array(data.attr['FLAGS']).include?(Net::IMAP::SEEN)] }
  end

  # Linhas que valem: gravadas desde o ponto de partida da caixa.
  def valendo
    ConversaCanal::EmailLido.where(sincronizado_em: @caixa.ponto_de_partida..)
  end

  # { uid => { id:, message_id:, seen: } } das linhas cujo UID vale na UIDVALIDITY atual.
  def linhas_por_uid(uids)
    colunas = valendo.where(inbox_id: inbox.id, uidvalidity: uidvalidity, uid: uids).pluck(:uid, :id, :message_id, :seen_no_servidor)
    colunas.to_h { |uid, id, message_id, seen| [uid, { id: id, message_id: message_id, seen: seen }] }
  end

  # UID desconhecido: Message-ID (cache ou cabeçalho) e liga ao e-mail importado. Linha que vale (UIDVALIDITY nova, linha
  # criada pelo painel) ganha o UID e segue para a comparação; primeira vez (ou linha de antes do ponto de partida) só
  # grava o estado.
  def identificar(uids)
    mensagens = mensagens_por_uid(uids)
    return [{}, []] if mensagens.empty?

    colunas = valendo.where(message_id: mensagens.values.map(&:id)).pluck(:message_id, :id, :seen_no_servidor)
    existentes = colunas.to_h { |message_id, id, seen| [message_id, { id: id, message_id: message_id, seen: seen }] }
    com_linha, primeira_vez = mensagens.partition { |_uid, message| existentes.key?(message.id) }
    gravar_uids(com_linha)
    [com_linha.to_h.transform_values { |message| existentes[message.id] }, gravar_primeira_vez(primeira_vez)]
  end

  def mensagens_por_uid(uids)
    return {} if uids.empty?

    message_ids = ConversaCanal::MessageIdsDoServidor.new(imap: @imap, inbox: inbox, uidvalidity: uidvalidity).de(uids)
    return {} if message_ids.empty?

    por_source = inbox.messages.incoming.where(source_id: message_ids.values).index_by(&:source_id)
    message_ids.transform_values { |source_id| por_source[source_id] }.compact
  end

  def linha(message, uid, extra = {})
    { account_id: message.account_id, inbox_id: message.inbox_id, message_id: message.id, uid: uid, uidvalidity: uidvalidity }
      .merge(extra)
  end

  # rubocop:disable Rails/SkipsModelValidations
  def gravar_uids(com_linha)
    return if com_linha.empty?

    linhas = com_linha.map { |uid, message| linha(message, uid) }
    ConversaCanal::EmailLido.upsert_all(linhas, unique_by: :message_id, update_only: %i[uid uidvalidity])
  end

  # Grava por cima da linha de antes do ponto de partida, se houver (estamos no lock da caixa: ninguém mais grava).
  # Devolve os message_id que chegaram lidos depois do ponto de partida (contam como passagem para lido).
  def gravar_primeira_vez(primeira_vez)
    return [] if primeira_vez.empty?

    agora = Time.current
    linhas = primeira_vez.map do |uid, message|
      linha(message, uid, seen_no_servidor: @no_servidor[uid], desmarcado_no_servidor_em: nil, sincronizado_em: agora)
    end
    ConversaCanal::EmailLido.upsert_all(linhas, unique_by: :message_id)
    primeira_vez.filter_map { |uid, message| message.id if @no_servidor[uid] && message.created_at >= @caixa.ponto_de_partida }
  end
  # rubocop:enable Rails/SkipsModelValidations

  # [message_ids que passaram para lido, message_ids que passaram para não lido]
  def passar(conhecidas)
    para_lido = conhecidas.filter_map { |uid, estado| estado[:id] if @no_servidor[uid] && !estado[:seen] }
    para_nao_lido = conhecidas.filter_map { |uid, estado| estado[:id] if !@no_servidor[uid] && estado[:seen] }
    [ConversaCanal::EmailLido.passar!(para_lido, seen: true), ConversaCanal::EmailLido.passar!(para_nao_lido, seen: false)]
  end

  # Só o ÚLTIMO e-mail recebido de cada conversa decide.
  def aplicar(lidas, nao_lidas)
    Message.where(id: lidas + nao_lidas).includes(:conversation).map(&:conversation).uniq.each do |conversation|
      ultima = conversation.messages.incoming.reorder(created_at: :desc, id: :desc).first
      decidir(conversation, ultima, lidas, nao_lidas) if ultima
    end
  end

  def decidir(conversation, ultima, lidas, nao_lidas)
    if lidas.include?(ultima.id) && !lida?(conversation, ultima) && !ConversaCanal::EmailLido.nao_lida_pendente?(ultima.id)
      marcar_lida(conversation, ultima)
    elsif nao_lidas.include?(ultima.id) && lida?(conversation, ultima)
      marcar_nao_lida(conversation, ultima)
    end
  end

  def lida?(conversation, ultima)
    conversation.agent_last_seen_at.present? && conversation.agent_last_seen_at >= ultima.created_at
  end

  # Lida "pela caixa", como no Gmail: vale para todos, inclusive o responsável. Nunca antes do último recebido (relógio do
  # servidor do banco atrás do da aplicação não pode deixar a conversa não lida).
  def marcar_lida(conversation, ultima)
    ConversaCanal::LidoDaConversa.new(conversation).marcar!([ultima.created_at, Time.current].max, atualizar_responsavel: true)
  end

  # Espelho do `unread` do Api::V1::Accounts::ConversationsController: o lido fica 1 s antes do último recebido, para o
  # atendente e o responsável, com os contadores. Sem job para o servidor (foi o servidor que mudou).
  def marcar_nao_lida(conversation, ultima)
    ConversaCanal::LidoDaConversa.new(conversation).marcar!(ultima.created_at - 1.second, atualizar_responsavel: true)
  end
end

# "Lido" de um e-mail recebido, sincronizado com o servidor IMAP do cliente (#1870). Uma linha por Message recebida na
# caixa de e-mail: o UID no INBOX do servidor, a UIDVALIDITY em que esse UID vale e o último estado de \Seen sincronizado
# (lido no servidor ou escrito por nós). A conversa só muda aqui quando esse estado PASSA de um lado para o outro
# (ConversaCanal::EmailLidoDoServidor); é isso que impede o servidor de desfazer o que foi feito no painel e evita o laço
# painel -> servidor -> painel.
# `desmarcado_no_servidor_em`: quando o servidor tirou o \Seen de um e-mail que estava lido. O painel não regrava o \Seen
# por causa disso; só uma leitura nova aqui, depois dessa hora, volta a marcar (ConversaCanal::EmailLidoNoServidor).
class ConversaCanal::EmailLido < ApplicationRecord
  self.table_name = 'conversa_canal_email_lidos'

  FLAG = 'email_lido_sincronizado'.freeze
  # Linha sem mudança há mais que isso é de e-mail fora das duas janelas (2 dias na leitura, 30 na escrita): sai na
  # limpeza diária (ConversaCanal::LimparEmailLidosJob).
  RETENCAO = 30.days

  belongs_to :account
  belongs_to :inbox
  belongs_to :message

  # Caixa de e-mail que lê o servidor por IMAP, na conta com a flag ligada. Caixa só com encaminhamento (imap_enabled
  # falso) não tem servidor para ler nem escrever.
  def self.ligado?(inbox)
    channel = inbox&.channel
    channel.is_a?(Channel::Email) && channel.imap_enabled? && inbox.account.feature_enabled?(FLAG)
  end

  # Ligado e com a credencial em dia (caixa não marcada para reautorizar).
  def self.sincroniza?(inbox)
    ligado?(inbox) && !inbox.channel.reauthorization_required?
  end

  # Grava, em lote, o estado escrito ou lido no servidor para as mensagens dadas. Mensagem sem UID em `uids` não perde o
  # UID já conhecido. Sempre limpa `desmarcado_no_servidor_em`: o estado gravado passa a ser o de agora.
  def self.gravar!(mensagens, seen:, uids: {}, uidvalidity: nil)
    agora = Time.current
    com_uid, sem_uid = mensagens.partition { |message| uids.key?(message.id) }
    estado = { seen_no_servidor: seen, desmarcado_no_servidor_em: nil, sincronizado_em: agora }
    colunas = estado.keys
    # rubocop:disable Rails/SkipsModelValidations
    if com_uid.any?
      linhas = com_uid.map { |message| base(message).merge(estado, uid: uids[message.id], uidvalidity: uidvalidity) }
      upsert_all(linhas, unique_by: :message_id, update_only: colunas + %i[uid uidvalidity])
    end
    upsert_all(sem_uid.map { |message| base(message).merge(estado) }, unique_by: :message_id, update_only: colunas) if sem_uid.any?
    # rubocop:enable Rails/SkipsModelValidations
  end

  # Passagem atômica do \Seen (compara e troca): devolve só os message_id cuja linha estava no outro estado. Duas
  # gravações ao mesmo tempo (importação e painel) não contam a mesma passagem duas vezes.
  def self.passar!(ids, seen:)
    return [] if ids.empty?

    agora = Time.current
    desmarcado = seen ? nil : agora
    sql = sanitize_sql_array([<<~SQL.squish, seen, desmarcado, agora, agora, ids, !seen])
      UPDATE #{table_name} SET seen_no_servidor = ?, desmarcado_no_servidor_em = ?, sincronizado_em = ?, updated_at = ?
      WHERE id IN (?) AND seen_no_servidor = ? RETURNING message_id
    SQL
    connection.select_values(sql)
  end

  # "Marcar não lida" do painel ainda não escrito no servidor (#1870). Enquanto vale, a importação não conta a passagem
  # para lido desse e-mail (não desfaz o "não lida" daqui). Fica no Redis, não na linha: a linha só muda depois do
  # STORE ok. O job apaga ao escrever ou ao desistir e renova a marca a cada execução enquanto o pedido está na fila
  # (ConversaCanal::EmailLidoNoServidorJob#renovar_nao_lidas); a validade é a de cada renovação.
  NAO_LIDA_PENDENTE = 30.minutes

  def self.chave_da_nao_lida(message_id)
    "conversa_canal:email_lido:nao_lida_pendente:#{message_id}"
  end

  def self.nao_lida_pendente!(message)
    Redis::Alfred.set(chave_da_nao_lida(message.id), '1', ex: NAO_LIDA_PENDENTE.to_i)
  end

  def self.nao_lida_pendente?(message_id)
    Redis::Alfred.exists?(chave_da_nao_lida(message_id))
  end

  def self.nao_lida_resolvida!(message_id)
    Redis::Alfred.delete(chave_da_nao_lida(message_id))
  end

  def self.base(message)
    { account_id: message.account_id, inbox_id: message.inbox_id, message_id: message.id }
  end
  private_class_method :base

  # O UID gravado vale para a UIDVALIDITY atual. Servidor sem UIDVALIDITY (nil) compara nil com nil: o UID gravado sem
  # ela continua valendo, sem regravar linha nem buscar de novo a cada vez.
  def uid_valido?(uidvalidity_atual)
    uid.present? && uidvalidity == uidvalidity_atual
  end
end

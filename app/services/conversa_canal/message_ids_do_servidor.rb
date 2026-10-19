# Message-ID de cada UID do INBOX do cliente (#1870), lido do cabeçalho (BODY.PEEK, sem marcar lido) e comparado por
# igualdade, nunca por trecho. Usado pela importação (UID que ainda não conhecemos) e pela escrita (confirmar o resultado
# do UID SEARCH HEADER, que casa substring, antes do STORE).
# Cache por (caixa, UIDVALIDITY, UID) no Redis por mais que a janela da leitura: UID que não vira mensagem nossa
# (notificação, e-mail não importado) não tem o cabeçalho pedido de novo a cada minuto. O par UID/Message-ID não muda
# enquanto a UIDVALIDITY for a mesma (RFC 3501, 2.3.1.1), então o cache não envelhece errado.
class ConversaCanal::MessageIdsDoServidor
  PEDIDO = 'BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)]'.freeze
  # O servidor devolve a seção do jeito dele (maiúsculas e minúsculas variam): acha pelo começo, sem diferenciar.
  CABECALHO = 'BODY[HEADER'.freeze
  VALIDADE_DO_CACHE = 3.days

  def initialize(imap:, inbox:, uidvalidity:)
    @imap = imap
    @inbox = inbox
    @uidvalidity = uidvalidity
  end

  # { uid => message_id } dos UIDs dados que têm Message-ID.
  def de(uids)
    return {} if uids.empty?

    lembrados = lembrar(uids)
    buscados = buscar(uids - lembrados.keys)
    guardar(buscados)
    lembrados.merge(buscados).compact_blank
  end

  private

  def chave
    "conversa_canal:email_lido:message_ids:#{@inbox.id}:#{@uidvalidity || 'sem'}"
  end

  def lembrar(uids)
    uids.zip(Redis::Alfred.hmget(chave, uids.map(&:to_s))).to_h.compact
  end

  # Cabeçalho veio sem Message-ID: guarda vazio (não é pedido de novo). A seção nem veio na resposta: não guarda nada, e
  # o UID é pedido de novo na próxima.
  def buscar(uids)
    return {} if uids.empty?

    Array(@imap.uid_fetch(uids, [PEDIDO])).each_with_object({}) do |data, buscados|
      _nome, cabecalho = data.attr.find { |nome, _valor| nome.to_s.upcase.start_with?(CABECALHO) }
      buscados[data.attr['UID']] = Mail.read_from_string(cabecalho.to_s).message_id.to_s unless cabecalho.nil?
    end
  end

  def guardar(buscados)
    return if buscados.empty?

    Redis::Alfred.pipelined do |redis|
      buscados.each { |uid, message_id| redis.hset(chave, uid.to_s, message_id) }
      redis.expire(chave, VALIDADE_DO_CACHE.to_i)
    end
  end
end

# A PENDÊNCIA DE ENVIO de uma mensagem do publicador (decisão 7 do `AsyncPublisher`, rodada 8 da
# entrega 11): a marca `content_attributes['autonomia_envio_pendente'] = true` que diz "esta mensagem
# está no banco e o `SendReplyJob` dela NÃO entrou na fila". Quem a grava é a tentativa que falhou em
# reenviar; quem a lê é a tentativa seguinte, que acha a mensagem pelo token; quem a limpa é o reenvio
# que ENTROU. Token encontrado só quer dizer entregue quando não há esta pendência.
#
# A ESCRITA É UMA SÓ E ATÔMICA, no próprio UPDATE (`||` e `-` sobre o JSON): nem lê-modifica-escreve
# (perderia o que outra thread escrevesse em `content_attributes` no meio — o `external_error` do
# canal, por exemplo), nem callbacks da `Message` (o `after_update_commit` fala com o Redis, que é
# justamente quem está fora). O lock da conversa não entra: ele não fecharia a janela entre quem lê a
# marca e quem a grava — a tentativa que lesse antes da escrita diria `published`, a que gravou diz
# `blocked`, e a reemissão seguinte acha a marca; a escrita atômica é o que basta. A falha DESTA
# escrita (banco) é registrada com código fechado e não levanta: `marca_nao_gravada` deixa a tentativa
# seguinte cega para a pendência (o caso raro que a decisão 7 não cobre); `marca_nao_limpa` deixa uma
# marca velha, que a tentativa seguinte reenvia uma vez (no-op se o canal já confirmou).
#
# A FORMA NO BANCO (provada na rodada 8, `json_typeof(content_attributes)` = 'string'): o
# `store :content_attributes, coder: JSON` da `Message` sobre uma coluna `json` codifica DUAS vezes —
# a coluna guarda uma STRING JSON com o objeto dentro, não o objeto. Por isso o objeto é extraído com
# `#>> '{}'` (o texto do escalar), mesclado como jsonb, e regravado com `to_json(text)`. Um `||`
# direto sobre o escalar produzia um ARRAY, e o coder da `Message` deixava de conseguir ler a mensagem.
class Autonomia::Agents::Tools::PendenciaDeEnvio
  CHAVE = 'autonomia_envio_pendente'.freeze
  OBJETO_SQL = "COALESCE((content_attributes #>> '{}')::jsonb, '{}'::jsonb)".freeze
  MARCAR_SQL = "content_attributes = to_json((#{OBJETO_SQL} || CAST(:marca AS jsonb))::text)".freeze
  LIMPAR_SQL = "content_attributes = to_json((#{OBJETO_SQL} - CAST(:chave AS text))::text)".freeze

  # A mensagem carrega a pendência? Só vale sem `source_id` (o canal já confirmou → entregue, com marca
  # ou sem) e fora da nota privada (não vai ao canal).
  def self.pendente?(mensagem)
    marcada?(mensagem) && mensagem.source_id.blank? && !mensagem.private?
  end

  def self.marcada?(mensagem)
    mensagem.content_attributes.to_h[CHAVE] == true
  end

  # `contexto` diz de onde veio o pedido (`run=<id>` no publicador), para o log.
  def self.marcar(mensagem, contexto:)
    gravar(mensagem, MARCAR_SQL, 'marca_nao_gravada', contexto)
  end

  def self.limpar(mensagem, contexto:)
    gravar(mensagem, LIMPAR_SQL, 'marca_nao_limpa', contexto)
  end

  def self.gravar(mensagem, sql, motivo, contexto)
    binds = { marca: { CHAVE => true }.to_json, chave: CHAVE }
    Message.where(id: mensagem.id).update_all([sql, binds]) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] pendencia de envio nao gravada #{contexto} message=#{mensagem.id} motivo=#{motivo} causa=#{e.class}")
  end
  private_class_method :gravar
end

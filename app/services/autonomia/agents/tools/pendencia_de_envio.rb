# A PENDÊNCIA DE ENVIO de uma mensagem do publicador (decisão 7 do `AsyncPublisher`, rodada 8 da
# entrega 11): a marca `content_attributes['autonomia_envio_pendente'] = true` que diz "esta mensagem
# está no banco e o `SendReplyJob` dela NÃO entrou na fila", ao lado de `autonomia_tool_run_id`, a
# execução que a publicou (rodada 9: é por ela que o varredor reconfere a autorização antes de
# reenviar). Quem grava é a tentativa que falhou em reenviar; quem lê é a tentativa seguinte, que acha
# a mensagem pelo token, e o varredor (`ReapStaleRunsJob`), que acha pela marca (`marcadas`); quem
# limpa é o reenvio que ENTROU — ou quem abandona a pendência com motivo (`abandonar`). Token
# encontrado só quer dizer entregue quando não há esta pendência.
#
# A ESCRITA É UMA SÓ E ATÔMICA, no próprio UPDATE (`||` e `-` sobre o JSON): nem lê-modifica-escreve
# (perderia o que outra thread escrevesse em `content_attributes` no meio — o `external_error` do
# canal, por exemplo), nem callbacks da `Message` (o `after_update_commit` fala com o Redis, que é
# justamente quem está fora). A falha DESTA escrita (banco) é registrada com código fechado e não
# levanta: `marca_nao_gravada` deixa o varredor cego para a pendência (o caso raro que nem a rodada 9
# cobre); `marca_nao_limpa` deixa uma marca velha, que o varredor encontra e resolve
# (`canal_confirmou` se o envio já saiu; reenvio, se não).
#
# A FORMA NO BANCO (provada na rodada 8, `json_typeof(content_attributes)` = 'string'): o
# `store :content_attributes, coder: JSON` da `Message` sobre uma coluna `json` codifica DUAS vezes —
# a coluna guarda uma STRING JSON com o objeto dentro, não o objeto. Por isso o objeto é extraído com
# `#>> '{}'` (o texto do escalar), mesclado como jsonb, e regravado com `to_json(text)`. Um `||`
# direto sobre o escalar produzia um ARRAY, e o coder da `Message` deixava de conseguir ler a mensagem.
# A string JSON VAZIA (`""`; rodada 9, P3 do Codex) dá `''`, que `::jsonb` recusa: o `NULLIF` a trata
# como `{}`, igual ao NULL. A matriz (string com objeto, NULL, objeto direto, string vazia) está no spec.
#
# NA LEITURA (`marcadas`) o cast é PROTEGIDO, como no varredor de blobs: `CASE WHEN … IS JSON OBJECT`.
# Na escrita, uma linha que não fosse JSON falha sozinha e registrada; na varredura, ela derrubaria a
# passada inteira, e as outras mensagens ficariam sem recuperação por causa de uma.
class Autonomia::Agents::Tools::PendenciaDeEnvio
  CHAVE = 'autonomia_envio_pendente'.freeze
  # O MESMO nome da marca do blob (`EntregaDeArquivo::EXECUCAO_CHAVE`), de propósito: é o mesmo
  # conceito — a execução que produziu isto — em dois lugares diferentes.
  EXECUCAO_CHAVE = 'autonomia_tool_run_id'.freeze
  OBJETO_SQL = "COALESCE(NULLIF(content_attributes #>> '{}', ''), '{}')::jsonb".freeze
  MARCAR_SQL = "content_attributes = to_json((#{OBJETO_SQL} || CAST(:marca AS jsonb))::text)".freeze
  LIMPAR_SQL = "content_attributes = to_json((#{OBJETO_SQL} - CAST(:chave AS text) - CAST(:execucao_chave AS text))::text)".freeze
  # `IS JSON` pede Postgres 16+ (CI e local: 16; produção: 18) — a mesma exigência de `blobs_sem_dono`.
  OBJETO_LIDO_SQL = "CASE WHEN (content_attributes #>> '{}') IS JSON OBJECT THEN (content_attributes #>> '{}')::jsonb END".freeze
  MARCADA_SQL = "#{OBJETO_LIDO_SQL} ? :chave".freeze

  # A mensagem carrega a pendência? Só vale sem `source_id` (o canal já confirmou → entregue, com marca
  # ou sem) e fora da nota privada (não vai ao canal).
  def self.pendente?(mensagem)
    marcada?(mensagem) && mensagem.source_id.blank? && !mensagem.private?
  end

  def self.marcada?(mensagem)
    mensagem.content_attributes.to_h[CHAVE] == true
  end

  # A execução que publicou a mensagem marcada, ou nil (marca sem execução: o varredor abandona).
  def self.execucao_id(mensagem)
    mensagem.content_attributes.to_h[EXECUCAO_CHAVE]
  end

  # As mensagens do publicador que carregam a marca, criadas desde `desde`, as mais antigas primeiro,
  # até `limite`. O filtro pela marca é SQL (a chave existe no objeto), sobre `created_at`
  # (`index_messages_on_created_at`) e `sender_type` — não há índice para a marca; a janela é o que
  # limita a leitura. Os binds são NOMEADOS para o `?` do jsonb não ser tomado por posição.
  def self.marcadas(desde:, limite:)
    Message.where(sender_type: 'AgentBot').where(created_at: desde..)
           .where(MARCADA_SQL, chave: CHAVE).order(:id).limit(limite)
  end

  # `contexto` diz de onde veio o pedido (`run=<id>` no publicador e na retomada; `varredor`), para o log.
  def self.marcar(mensagem, run_id:, contexto:)
    gravar(mensagem, MARCAR_SQL, 'marca_nao_gravada', contexto, marca: { CHAVE => true, EXECUCAO_CHAVE => run_id }.to_json)
  end

  def self.limpar(mensagem, contexto:)
    gravar(mensagem, LIMPAR_SQL, 'marca_nao_limpa', contexto, chave: CHAVE, execucao_chave: EXECUCAO_CHAVE)
  end

  # A pendência que NÃO vai ser resolvida por envio: a marca sai e o motivo, FECHADO, fica no log —
  # `execucao_morta`, `vinculo_mudou`, `ferramenta_recusou`, `canal_confirmou`, `nota_privada`,
  # `sem_conversa`, `sem_execucao`. (`ferramenta_recusou` passou a chegar aqui na rodada 4 da entrega
  # 8: a retomada identifica a entrega pelo TOKEN da mensagem e pergunta à ferramenta se ela ainda
  # entregaria aquilo — a proposta de uma cotação já refeita não é reenviada, é abandonada.)
  def self.abandonar(mensagem, motivo:, contexto:)
    limpar(mensagem, contexto: contexto)
    Rails.logger.warn("[autonomia][tool][async] envio pendente abandonado #{contexto} message=#{mensagem.id} motivo=#{motivo}")
  end

  def self.gravar(mensagem, sql, motivo, contexto, binds)
    Message.where(id: mensagem.id).update_all([sql, binds]) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.warn("[autonomia][tool][async] pendencia de envio nao gravada #{contexto} message=#{mensagem.id} motivo=#{motivo} causa=#{e.class}")
  end
  private_class_method :gravar
end

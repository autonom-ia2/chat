# #2211 — a seção "Mensagens" da busca da lista: as mais recentes que têm todas as palavras, no texto ou no áudio
# transcrito, só das conversas que a pessoa pode ler. Devolve os ids, do mais recente para o mais antigo.
#
# Dois caminhos, porque nenhum serve sozinho:
# - termo comum ("seguro" está em 1 de cada 10 mensagens): o índice trigram acha dezenas de milhares de candidatas e
#   cada uma é conferida pela expressão sem acento. Mais rápido é olhar as mensagens visíveis mais recentes, em ordem,
#   e parar nas primeiras LIMITE que batem;
# - termo raro: andar pelas recentes leria a conta inteira. O índice acha as poucas candidatas direto.
# Primeiro as recentes, dentro da JANELA_DE_RECENTES. Se ali já há LIMITE, elas são as mais recentes de todas (tudo fora
# da janela é mais antigo) e a busca para. Se não, vale o índice.
class SearchService::MensagensDaLista
  LIMITE = 15
  MESES = 12
  TIPOS = %w[incoming outgoing template].freeze
  # Quantas mensagens visíveis, das mais recentes, são conferidas antes de ir ao índice. Com a expressão sem acento
  # (~10 µs por mensagem), 3 mil ficam abaixo de 70 ms mesmo para quem vê uma caixa só, na carga da hub.
  JANELA_DE_RECENTES = 3000
  TRANSCRICAO = "(attachments.meta ->> 'transcribed_text')".freeze

  def initialize(conta:, conversas_permitidas:, palavras:)
    @conta = conta
    @permitidas = conversas_permitidas.reselect(:id)
    @palavras = palavras
  end

  def ids
    recentes = nas_recentes
    recentes.size >= LIMITE ? recentes : ActiveRecord::Base.connection.select_values(pelo_indice)
  end

  private

  def da_conta
    @conta.messages.where(created_at: MESES.months.ago.., message_type: TIPOS)
  end

  def palavras_em(expressao)
    SearchService::SemAcento.todas_as_palavras(expressao, @palavras)
  end

  # As palavras entram por where com bind, cada parte na sua relação; nada de `?` por cima de SQL já montado.
  def nas_recentes
    janela = da_conta.where(conversation_id: @permitidas).reselect('messages.id, messages.created_at, messages.content')
                     .reorder('messages.created_at DESC, messages.id DESC').limit(JANELA_DE_RECENTES)
    recentes = Message.unscoped.from(janela, :recentes)
    no_audio = Attachment.unscoped.where('attachments.message_id = recentes.id').where(*palavras_em(TRANSCRICAO))
    recentes.where(*palavras_em('recentes.content')).or(recentes.where(no_audio.arel.exists))
            .reorder(Arel.sql('recentes.created_at DESC, recentes.id DESC')).limit(LIMITE)
            .pluck(Arel.sql('recentes.id'))
  end

  # Texto e áudio em consultas separadas, cada uma no seu índice trigram e num CTE MATERIALIZED: o Postgres acha as
  # mensagens pelo índice primeiro e só depois confere o acesso e ordena. Sem isso, para quem vê poucas caixas, ele
  # descia conversa por conversa e lia todas as mensagens delas (2 s com o volume da hub).
  def pelo_indice
    base = da_conta.reselect('messages.id, messages.created_at, messages.conversation_id')
    texto = base.where(*palavras_em('messages.content'))
    # Uma linha por mensagem, mesmo com mais de um áudio transcrito.
    audio = base.joins(:attachments).distinct.where(*palavras_em(TRANSCRICAO))
    permitidas = @permitidas.to_sql
    <<~SQL.squish
      SELECT id FROM (
        WITH texto AS MATERIALIZED (#{texto.to_sql}), audio AS MATERIALIZED (#{audio.to_sql})
        (SELECT id, created_at FROM texto WHERE conversation_id IN (#{permitidas}) ORDER BY created_at DESC, id DESC LIMIT #{LIMITE})
        UNION
        (SELECT id, created_at FROM audio WHERE conversation_id IN (#{permitidas}) ORDER BY created_at DESC, id DESC LIMIT #{LIMITE})
      ) achadas ORDER BY created_at DESC, id DESC LIMIT #{LIMITE}
    SQL
  end
end

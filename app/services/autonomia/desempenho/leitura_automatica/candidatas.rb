# As conversas que a leitura automática precisa ler (#2301): as da conta com mensagem pública (do cliente ou da
# equipe) depois de onde a leitura parou e até o corte, e em que o agente falou alguma vez. "Onde parou" é o
# `lida_ate_em` da leitura da conversa. A conversa que nunca foi lida usa o mais antigo entre o piso da rodada e o
# `piso_sem_leitura` (o corte menos 30 dias): a conversa que a carga não leu, ou que chegou com mensagens antigas
# (histórico do WhatsApp, importação), entra na fila mesmo com todas as mensagens antes do piso. Depois de lida (ou
# marcada como não lida), ela tem leitura e passa a usar o `lida_ate_em`. Essas, antes do piso, não entram em
# `mais_antiga`: o "Lido até" fala do piso para a frente e não recua 30 dias por causa delas.
# Ordem: a que espera há mais tempo primeiro (a mensagem nova mais antiga), para o teto e o limite da rodada não
# deixarem sempre as mesmas para trás.
class Autonomia::Desempenho::LeituraAutomatica::Candidatas
  def initialize(account:, sujeito_type:, sujeito_id:, remetentes:, piso:, corte:, piso_sem_leitura: piso) # rubocop:disable Metrics/ParameterLists
    @account = account
    @sujeito_type = sujeito_type
    @sujeito_id = sujeito_id
    @remetentes = Array(remetentes)
    @piso_da_rodada = piso
    @piso = [piso, piso_sem_leitura].min
    @corte = corte
  end

  # Os ids das conversas, na ordem de leitura.
  def ids
    return [] if @remetentes.empty?

    ActiveRecord::Base.connection.select_rows(sql).map { |id, _desde| id.to_i }
  end

  # A mensagem nova mais antiga entre as conversas da fila (nil quando não há nenhuma): até antes dela, tudo foi lido.
  def mais_antiga
    return nil if @remetentes.empty?

    piso = ActiveRecord::Base.connection.quote(@piso_da_rodada)
    valor = ActiveRecord::Base.connection.select_value("SELECT MIN(desde) FROM (#{sql}) fila WHERE desde > #{piso}")
    valor && ActiveRecord::Type::DateTime.new.cast(valor)
  end

  private

  def sql
    binds = { conta: @account.id, tipo: @sujeito_type, sujeito: @sujeito_id, piso: @piso, corte: @corte }
    ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, binds])
      SELECT c.id, MIN(m.created_at) AS desde
      FROM conversations c
      LEFT JOIN autonomia_desempenho_leituras l
        ON l.conversation_id = c.id AND l.account_id = :conta AND l.sujeito_type = :tipo AND l.sujeito_id = :sujeito
      JOIN messages m
        ON m.conversation_id = c.id AND m.account_id = :conta AND m.message_type IN (0, 1) AND NOT COALESCE(m.private, FALSE)
       AND m.created_at > COALESCE(l.lida_ate_em, :piso) AND m.created_at <= :corte
      WHERE c.account_id = :conta
        AND EXISTS (SELECT 1 FROM messages a WHERE a.conversation_id = c.id AND a.account_id = :conta AND a.message_type = 1
                    AND (#{do_agente}))
      GROUP BY c.id
      ORDER BY MIN(m.created_at), c.id
    SQL
  end

  # Quem fala pelo agente: pares [tipo do remetente, id] da ficha, como no painel (Autonomia::Desempenho::Mensagens).
  def do_agente
    @remetentes.map do |tipo, id|
      ActiveRecord::Base.sanitize_sql_array(['(a.sender_type = ? AND a.sender_id = ?)', tipo.to_s, id.to_i])
    end.join(' OR ')
  end
end

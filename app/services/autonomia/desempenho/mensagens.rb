# Mensagens e tempo de resposta do agente (#2251), ao vivo do banco, nas conversas que o painel leu. São os números do
# painel que não dependem da leitura da IA. Mesma regra do protótipo:
# - autor: contato (entrada), agente (saída pública de um dos `remetentes` da ficha), equipe (outra saída pública),
#   notas (saída privada); o resto (eventos) não conta;
# - tempo de resposta: da primeira mensagem do contato depois da última resposta (do agente ou da equipe) até a
#   resposta do agente; a resposta da equipe zera a espera. O dia é o da resposta, no fuso da ficha.
# Uma consulta para as contagens por dia, só na `faixa` de datas que o painel mostra (o período e o anterior); outra
# para as respostas, com o histórico das conversas que têm mensagem na faixa (a espera pode ter começado antes); e uma
# terceira para a equipe por mês, que é do histórico. Com `visiveis`, só as conversas que a pessoa vê.
class Autonomia::Desempenho::Mensagens
  AUTORES = %w[contato agente equipe notas].freeze
  CINCO_MINUTOS = 300
  UMA_HORA = 3600

  # `faixa`: Date..Date no fuso (nil = tudo).
  def initialize(account:, sujeito_type:, sujeito_id:, remetentes:, fuso:, visiveis: nil, faixa: nil) # rubocop:disable Metrics/ParameterLists
    @account = account
    @sujeito_type = sujeito_type
    @sujeito_id = sujeito_id
    @remetentes = Array(remetentes)
    @fuso = ActiveSupport::TimeZone[fuso.to_s]&.tzinfo&.name || 'UTC'
    @visiveis = visiveis
    @faixa = faixa
  end

  # [mensagens, tempo] do período [inicio, fim] (datas no fuso da ficha, inclusivas).
  def call(inicio, fim)
    soma = Hash.new(0)
    por_dia.each { |(dia, autor), n| soma[autor] += n if dia.between?(inicio, fim) }
    [mensagens(soma), tempo(respostas.filter_map { |dia, segundos| segundos if dia.between?(inicio, fim) }.sort)]
  end

  # Mensagens da equipe por mês (AAAA-MM), até `ate`; o mês com mensagem e sem a equipe aparece com 0.
  def equipe_por_mes(ate)
    linhas = ActiveRecord::Base.connection.select_rows(sql_equipe_por_mes(ate))
    linhas.map { |mes, n| { 'mes' => mes, 'n' => n.to_i } }
  end

  private

  def mensagens(soma)
    out = AUTORES.index_with { |autor| soma[autor] }
    out['agente_por_mensagem_do_contato'] = soma['contato'].zero? ? nil : Rational(soma['agente'].to_f / soma['contato']).round(1, half: :even).to_f
    out
  end

  # Mediana e p90 pelo índice (a mediana de lista par fica com o de cima), segundos inteiros arredondados ao par.
  def tempo(latencias)
    return { 'medidas' => 0, 'mediana_seg' => nil, 'p90_seg' => nil, 'acima_5_min' => 0, 'acima_1_h' => 0 } if latencias.empty?

    { 'medidas' => latencias.size, 'mediana_seg' => segundos(latencias[latencias.size / 2]),
      'p90_seg' => segundos(latencias[(latencias.size * 0.9).floor]),
      'acima_5_min' => latencias.count { |x| x > CINCO_MINUTOS }, 'acima_1_h' => latencias.count { |x| x > UMA_HORA } }
  end

  def segundos(valor) = valor.round(0, half: :even).to_i

  # {[dia, autor] => quantidade}
  def por_dia
    @por_dia ||= ActiveRecord::Base.connection.select_rows(sql_por_dia).to_h { |dia, autor, n| [[Date.iso8601(dia.to_s), autor], n.to_i] }
  end

  # [[dia, segundos]]
  def respostas
    @respostas ||= ActiveRecord::Base.connection.select_rows(sql_respostas).map do |dia, segundos|
      [Date.iso8601(dia.to_s), BigDecimal(segundos.to_s)]
    end
  end

  def sql_equipe_por_mes(ate)
    sanitize(<<~SQL.squish, ate: ate.iso8601)
      WITH m AS (#{mensagens_com_autor(recorte: nil)}),
      d AS (SELECT (created_at AT TIME ZONE 'UTC' AT TIME ZONE :fuso)::date AS dia, autor FROM m WHERE autor <> 'evento')
      SELECT to_char(dia, 'YYYY-MM') AS mes, COUNT(*) FILTER (WHERE autor = 'equipe')
      FROM d WHERE dia <= CAST(:ate AS date) GROUP BY 1 ORDER BY 1
    SQL
  end

  def sql_por_dia
    sanitize(<<~SQL.squish)
      WITH m AS (#{mensagens_com_autor})
      SELECT (created_at AT TIME ZONE 'UTC' AT TIME ZONE :fuso)::date AS dia, autor, COUNT(*)
      FROM m WHERE autor <> 'evento' GROUP BY 1, 2
    SQL
  end

  # O bloco de uma mensagem é quantas respostas (agente ou equipe) vieram antes dela na conversa. Cada bloco termina
  # na resposta que o fecha, então a espera dessa resposta começa na primeira mensagem do contato do mesmo bloco. Só
  # janelas, sem juntar a consulta com ela mesma.
  def sql_respostas
    sanitize(<<~SQL.squish)
      WITH m AS (#{mensagens_com_autor(recorte: :conversas_da_faixa)}),
      c AS (
        SELECT conversation_id, created_at, autor,
               COUNT(*) FILTER (WHERE autor IN ('agente', 'equipe'))
                 OVER (PARTITION BY conversation_id ORDER BY created_at, id ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS bloco
        FROM m WHERE autor IN ('contato', 'agente', 'equipe')
      ),
      d AS (
        SELECT created_at, autor,
               MIN(created_at) FILTER (WHERE autor = 'contato') OVER (PARTITION BY conversation_id, bloco) AS desde
        FROM c
      )
      SELECT (created_at AT TIME ZONE 'UTC' AT TIME ZONE :fuso)::date, EXTRACT(EPOCH FROM created_at - desde)
      FROM d WHERE autor = 'agente' AND desde IS NOT NULL
    SQL
  end

  # `recorte`: :faixa (só as mensagens da faixa), :conversas_da_faixa (o histórico até o fim da faixa das conversas que
  # têm mensagem nela: a espera de uma resposta pode ter começado muito antes) ou nil (tudo).
  def mensagens_com_autor(recorte: :faixa)
    <<~SQL.squish
      SELECT m.id, m.conversation_id, m.created_at,
             CASE WHEN m.message_type = 0 THEN 'contato'
                  WHEN m.message_type = 1 AND COALESCE(m.private, FALSE) THEN 'notas'
                  WHEN m.message_type = 1 AND (#{do_agente}) THEN 'agente'
                  WHEN m.message_type = 1 THEN 'equipe'
                  ELSE 'evento' END AS autor
      FROM messages m
      WHERE m.account_id = :conta
        AND m.conversation_id IN (SELECT conversation_id FROM autonomia_desempenho_leituras
                                  WHERE account_id = :conta AND sujeito_type = :tipo AND sujeito_id = :sujeito)
        #{so_visiveis} #{recorte_sql(recorte)}
    SQL
  end

  def recorte_sql(recorte)
    return '' if @faixa.nil? || recorte.nil?

    zona = ActiveSupport::TimeZone[@fuso]
    desde = zona.parse(@faixa.first.iso8601).beginning_of_day.utc
    ate = zona.parse(@faixa.last.iso8601).end_of_day.utc
    if recorte == :faixa
      ActiveRecord::Base.sanitize_sql_array(['AND m.created_at BETWEEN ? AND ?', desde, ate])
    else
      ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, desde, ate, ate])
        AND m.conversation_id IN (SELECT a.conversation_id FROM messages a WHERE a.account_id = :conta AND a.created_at BETWEEN ? AND ?)
        AND m.created_at <= ?
      SQL
    end
  end

  # A relation das conversas que a pessoa vê vira subconsulta (o SQL é o do próprio Rails, sem texto de fora).
  def so_visiveis
    @visiveis ? "AND m.conversation_id IN (#{@visiveis.select(:id).to_sql})" : ''
  end

  # Quem fala pelo agente: pares [tipo do remetente, id], da ficha (o robô e, quando ele escreve por um usuário da
  # API, esse usuário).
  def do_agente
    return 'FALSE' if @remetentes.empty?

    @remetentes.map do |tipo, id|
      ActiveRecord::Base.sanitize_sql_array(['(m.sender_type = ? AND m.sender_id = ?)', tipo.to_s, id.to_i])
    end.join(' OR ')
  end

  def sanitize(sql, extras = {})
    binds = { fuso: @fuso, conta: @account.id, tipo: @sujeito_type, sujeito: @sujeito_id }.merge(extras)
    ActiveRecord::Base.sanitize_sql_array([sql, binds])
  end
end

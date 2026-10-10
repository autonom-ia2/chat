# Tempo de resposta das conversas de anúncio (#1110, F5, D5.6): quanto o cliente que chegou por anúncio esperou
# pela primeira resposta. Vale qualquer resposta de verdade — a pessoa, o agente da plataforma ou o eco do
# celular —, porque o que muda a venda é o cliente ser respondido. O número é a mediana: uma conversa respondida
# no dia seguinte não distorce o resto.
#
# `first_reply_created_at` e `first_response` não servem (no WAHA a conversa é uma só, e o agente Autonom.ia não
# aparece em `reply_time`), então o cálculo sai de `messages`, a partir do primeiro toque da conversa no período:
# 1. a primeira mensagem do cliente desde o toque (com 1 min de tolerância entre o toque e a mensagem que o criou);
# 2. a primeira saída pública depois dela que não seja boas-vindas/fora de horário (`template`), atividade,
#    automação (`automation_rule_id`) nem disparo de campanha (`campaign_id`, `whatsapp_api_campaign_id`).
# Sem resposta e com a entrada há mais de TARGET_SECONDS, conta como sem resposta; mais recente que isso, ainda
# está no prazo e não conta.
#
# Uma consulta só, com LATERAL sobre as conversas, pelo índice (conversation_id, account_id, message_type, created_at).
# `content_attributes` é `store ... coder: JSON` numa coluna json: o Rails grava o hash como STRING JSON dentro do
# json, e `->> 'automation_rule_id'` direto devolveria sempre NULL (a automação contaria como resposta). Por isso
# a string é desembrulhada (`#>> '{}'`) antes de ler a chave; objeto json (linha antiga ou gravada à mão) vale como está.
class Crm::MetaAds::Panel::ResponseTime
  TARGET_SECONDS = 300

  QUERY = <<~SQL.squish.freeze
    SELECT starts.conversation_id,
           EXTRACT(EPOCH FROM (reply.created_at - incoming.created_at)) AS seconds,
           incoming.created_at < :due AS overdue
      FROM (%<starts>s) starts
      JOIN LATERAL (
        SELECT m.created_at FROM messages m
         WHERE m.conversation_id = starts.conversation_id AND m.account_id = :account_id
           AND m.message_type = :incoming AND m.created_at >= starts.started_at - interval '1 minute'
         ORDER BY m.created_at LIMIT 1
      ) incoming ON true
      LEFT JOIN LATERAL (
        SELECT m.created_at FROM messages m
         WHERE m.conversation_id = starts.conversation_id AND m.account_id = :account_id
           AND m.message_type = :outgoing AND m.private = false AND m.created_at > incoming.created_at
           AND (CASE json_typeof(m.content_attributes)
                  WHEN 'string' THEN (m.content_attributes #>> '{}')::jsonb
                  ELSE m.content_attributes::jsonb END ->> 'automation_rule_id') IS NULL
           AND (m.additional_attributes ->> 'campaign_id') IS NULL
           AND (m.additional_attributes ->> 'whatsapp_api_campaign_id') IS NULL
         ORDER BY m.created_at LIMIT 1
      ) reply ON true
  SQL

  def initialize(account_id:, range:)
    @account_id = account_id
    @range = range
  end

  def payload
    seconds = by_conversation.values.select { |row| row[:answered] }.pluck(:seconds)
    {
      days: ((@range.end - @range.begin) / 1.day).ceil, median_seconds: median(seconds), answered: seconds.size,
      unanswered: by_conversation.values.count { |row| !row[:answered] }, slow: seconds.count { |value| value > TARGET_SECONDS },
      target_seconds: TARGET_SECONDS
    }
  end

  # { conversation_id => { seconds:, answered: } }, só das conversas que contam (respondidas ou vencidas).
  def by_conversation
    @by_conversation ||= rows.each_with_object({}) do |(conversation_id, seconds, overdue), all|
      if seconds
        all[conversation_id] = { seconds: seconds.to_f.round, answered: true }
      elsif overdue
        all[conversation_id] = { seconds: nil, answered: false }
      end
    end
  end

  private

  # O início de cada conversa é o menor toque dela no período, com ou sem anúncio (não o Cohort#touches, que
  # guarda o primeiro toque com anúncio).
  def starts
    Crm::MetaAdLink.where(account_id: @account_id, touched_at: @range).group(:conversation_id)
                   .select('conversation_id, MIN(touched_at) AS started_at')
  end

  def rows
    sql = ActiveRecord::Base.sanitize_sql(
      [format(QUERY, starts: starts.to_sql), { account_id: @account_id, due: Time.current - TARGET_SECONDS,
                                               incoming: Message.message_types[:incoming], outgoing: Message.message_types[:outgoing] }]
    )
    ActiveRecord::Base.connection.select_all(sql).cast_values
  end

  def median(values)
    return if values.empty?

    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : ((sorted[middle - 1] + sorted[middle]) / 2.0).round
  end
end

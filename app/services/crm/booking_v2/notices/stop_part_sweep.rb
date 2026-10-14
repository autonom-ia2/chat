# Conferência da mensagem 2 do aviso com botão (#1562, `NoticeStopPartJob`), a cada rodada do `NoticeDispatchJob`.
#
# Dois casos, os dois deixando o aviso `sent` (a mensagem 1 saiu) com `error_code: stop_part_failed` e avisando o
# responsável uma vez por aviso, sem reenviar nada:
# - a 2 foi marcada `failed` depois, pelo provedor (`#flag_failed!`, nas últimas FAILED_CHECK);
# - a 2 não existe GRACE depois do aviso (o job se perdeu: processo morto entre o aviso e o enfileiramento, Redis fora)
#   (`#flag_missing!`). Aviso "com botão" é o que tem o `rich_message` na mensagem 1: é o único caminho que o põe, então
#   não precisa de campo novo no aviso. Só até MISSING_UNTIL, porque o job não cria a 2 depois de `WINDOW`.
# Cliente que parou os avisos ou reunião que não está mais marcada (`NoticeStopPartJob.wanted?`): sem alerta.
#
# Busca em páginas pelo id (sem cortar casos), dentro das janelas de tempo. A marca da 2 é conferida em Ruby
# (`content_attributes` é json gravado como texto, `->>` devolve NULL). Um aviso com problema não para os outros.
class Crm::BookingV2::Notices::StopPartSweep
  Job = Crm::BookingV2::NoticeStopPartJob
  PAGE = 200
  FAILED_CHECK = 2.hours
  GRACE = 5.minutes
  MISSING_UNTIL = Job::WINDOW + GRACE
  # Limite do índice (status, due_at): o aviso sai no minuto em que vence.
  DUE_WINDOW = FAILED_CHECK + 1.day
  # Mensagens `failed` da conversa da 1, criadas depois dela e pelo mesmo remetente (a 2 sai com o remetente da 1).
  STOP_JOIN = <<~SQL.squish.freeze
    INNER JOIN messages notice_messages ON notice_messages.id = crm_meeting_notices.message_id
    INNER JOIN messages stop_messages ON stop_messages.conversation_id = notice_messages.conversation_id
      AND stop_messages.id > notice_messages.id
      AND stop_messages.sender_type IS NOT DISTINCT FROM notice_messages.sender_type
      AND stop_messages.sender_id IS NOT DISTINCT FROM notice_messages.sender_id
  SQL

  def perform
    flag_failed!
    flag_missing!
  end

  private

  def flag_failed!
    scope = recent_sent(FAILED_CHECK.ago).joins(STOP_JOIN)
                                         .where(stop_messages: { status: Message.statuses[:failed] })
                                         .where('stop_messages.created_at >= ?', FAILED_CHECK.ago)
    each_page(scope, 'stop_messages.id', 'crm_meeting_notices.id') do |pairs|
      messages = Message.where(id: pairs.map(&:first)).index_by(&:id)
      flag!(pairs.select { |message_id, notice_id| Job.stop_part_of?(messages[message_id], notice_id) }.map(&:last).uniq, 'stop_failed')
    end
  end

  def flag_missing!
    scope = recent_sent(MISSING_UNTIL.ago).where('crm_meeting_notices.sent_at <= ?', GRACE.ago).where.not(message_id: nil)
    each_page(scope, 'crm_meeting_notices.id', 'crm_meeting_notices.message_id') do |pairs|
      firsts = Message.where(id: pairs.map(&:last)).index_by(&:id)
      flag!(pairs.select { |notice_id, message_id| missing?(notice_id, firsts[message_id]) }.map(&:first), 'stop_missing')
    end
  end

  def recent_sent(since)
    Crm::MeetingNotice.sent.where(error_code: nil).where('crm_meeting_notices.due_at > ?', DUE_WINDOW.ago)
                      .where('crm_meeting_notices.sent_at > ?', since)
  end

  # Páginas pelo par (key, other), em ordem, até acabar. O par, e não só a key: a mesma mensagem falha pode aparecer
  # para mais de um aviso da conversa. `key` e `other` são as colunas fixas desta classe, nunca entrada de fora.
  def each_page(scope, key, other)
    last = [0, 0]
    loop do
      rows = scope.where("(#{key}, #{other}) > (?, ?)", *last).reorder(Arel.sql("#{key}, #{other}")).limit(PAGE)
                  .pluck(Arel.sql(key), Arel.sql(other))
      break if rows.empty?

      yield rows
      break if rows.size < PAGE

      last = rows.last
    end
  end

  # Só aviso com botão (a 1 traz o `rich_message`) cuja 1 não falhou (essa é o `delivery_failed`) e sem a 2.
  def missing?(notice_id, first)
    return false if first.nil? || first.failed?
    return false unless first.content_attributes.to_h.with_indifferent_access.dig(RichMessages::KEY, 'type') == Crm::BookingV2::Notices::Button::TYPE

    !Job.stop_created?(notice_id, first)
  end

  def flag!(ids, why)
    Crm::MeetingNotice.includes(meeting: [:account, { card: :contact }]).where(id: ids).find_each do |notice|
      Job.stop_failed!(notice, why: why) if Job.wanted?(notice.meeting)
    rescue StandardError => e
      Job.report(notice.id, e, account: notice.account, what: 'stop part sweep')
    end
  end
end

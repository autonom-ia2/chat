# Mensagem 2 do aviso com botão (#1562): "Não quer mais receber estes avisos?" + botão "Parar avisos".
#
# Por que um job, e não criar a 2 junto com a 1: cada mensagem enfileira o próprio `SendReplyJob` na criação
# (`Message#send_reply`, fila `high`). Com o Sidekiq em paralelo, a 2 podia chegar ao cliente ANTES do aviso. Então o
# `Notices::Sender` cria só a 1 e enfileira este job com um atraso curto (WAIT). Ele só cria a 2 depois que a 1 saiu de
# fato: a Meta aceitou e a mensagem ganhou o `source_id` (wamid). O `Message` não tem estado "enviando": `sent` é o
# padrão na criação, então quem diz que saiu é o `source_id`. Ainda sem ele, reagenda; depois de MAX_ATTEMPTS
# (~1 min) desiste e avisa o responsável. Mensagem 1 `failed`: a 2 não sai; quem avisa o responsável é o
# `NoticeDispatchJob` (`delivery_failed`, no minuto seguinte), como em qualquer aviso que não saiu.
#
# Disparar a 2 do `SendReplyJob` da 1 seria mais direto, mas exigiria um prepend no envio comum do WhatsApp (o mesmo
# caminho de todas as mensagens do painel). Aqui tudo fica nos arquivos do agendamento.
#
# Com o aviso travado (`with_lock`), antes de criar:
# - o cliente parou os avisos ou a reunião não está mais marcada (`Sender.stop_reason`, `scheduled?`): não cria e não
#   alerta (motivo quieto, como no `Sender`);
# - idempotência: não cria se já houver a 2 (marca `crm_booking_notice_part: 'stop'` + `crm_booking_notice_id`) na
#   conversa, entre a criação da 1 e WINDOW depois. Passada a WINDOW o job não cria mais (desiste com alerta), então a
#   conferência sempre cobre o período em que a 2 pode existir.
# Mesma conversa, mesmo remetente e o mesmo `Notices::Delivery` da 1; o link é o do botão da 1 com `?stop_notices=1`.
#
# Falha (erro ao criar, mensagem 1 apagada, desistência): o aviso continua `sent` (a 1 saiu), ganha
# `error_code: stop_part_failed` e o responsável é avisado UMA vez por aviso (`AgentAlert` `notice_stop_failed`). Nada
# é reenviado. Erro de banco (DB_ERRORS) vai ao log e ao tracker e é relançado para o retry do Sidekiq: a trava, a
# conferência e o `error_code` seguram a repetição. Job perdido e a 2 marcada `failed` depois: `Notices::StopPartSweep`,
# no cron.
class Crm::BookingV2::NoticeStopPartJob < ApplicationJob
  queue_as :default

  WAIT = 10.seconds
  MAX_ATTEMPTS = 6
  # Depois da criação da 1: até quando a 2 pode ser criada e, por isso, onde a conferência de duplicata procura.
  WINDOW = 30.minutes
  STOP_PART = 'stop'.freeze
  STOP_PART_FAILED = 'stop_part_failed'.freeze
  DB_ERRORS = [ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid].freeze

  # Enfileirar falhou (Redis fora): a 2 não vai sair, então o responsável fica sabendo.
  def self.enqueue(notice, attempt: 1)
    set(wait: WAIT).perform_later(notice.id, attempt)
  rescue StandardError => e
    report(notice.id, e, account: notice.account)
    stop_failed!(notice, why: 'enqueue_failed')
  end

  # Marca só aviso `sent` ainda sem marca, então o alerta sai uma vez por aviso. Falhar o alerta não desfaz a marca:
  # vai ao log e ao tracker, como no `NoticeDispatchJob#alert_failure`.
  def self.stop_failed!(notice, why:)
    Rails.logger.error("CRM booking notice #{notice.id} stop part failed: #{why}")
    changed = Crm::MeetingNotice.where(id: notice.id, status: :sent, error_code: nil)
                                .update_all(error_code: STOP_PART_FAILED, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    alert!(notice) if changed.positive?
  end

  def self.alert!(notice)
    Crm::BookingV2::Notices::AgentAlert.new(notice.meeting, 'notice_stop_failed', { kind: notice.kind, reason: STOP_PART_FAILED }).perform
  rescue StandardError => e
    report(notice.id, e, account: notice.account, what: 'alert')
  end

  def self.report(notice_id, error, account:, what: 'stop part')
    Rails.logger.error("CRM booking notice #{notice_id} #{what} error: #{error.class.name}")
    ChatwootExceptionTracker.new(error, account: account).capture_exception
  end

  # A 2 deste aviso, se já existe: na conversa da 1, criada entre ela e WINDOW depois. A marca é conferida em Ruby
  # (`content_attributes` é json gravado como texto, `->>` devolve NULL).
  def self.stop_created?(notice_id, first)
    first.conversation.messages.outgoing
         .where(created_at: first.created_at..(first.created_at + WINDOW)).where.not(id: first.id)
         .any? { |message| stop_part_of?(message, notice_id) }
  end

  # A 2 ainda faz sentido: reunião marcada e o cliente não parou os avisos (a mesma regra do `Sender`).
  def self.wanted?(meeting)
    meeting.scheduled? && Crm::BookingV2::Notices::Sender.stop_reason(meeting).nil?
  end

  def self.stop_part_of?(message, notice_id)
    return false if message.nil?

    mark = message.content_attributes.to_h.with_indifferent_access
    mark[:crm_booking_notice_part] == STOP_PART && mark[:crm_booking_notice_id] == notice_id
  end

  def perform(notice_id, attempt = 1)
    notice = Crm::MeetingNotice.includes(meeting: :account).find_by(id: notice_id)
    deliver(notice, attempt) if notice&.sent? && notice.error_code.nil?
  rescue StandardError => e
    failed_with!(notice_id, e)
  end

  private

  # Sempre log e tracker. Erro de banco relança (retry do Sidekiq); o resto marca o aviso, relido por id (o da
  # tentativa pode nem ter sido carregado).
  def failed_with!(notice_id, error)
    db_error = DB_ERRORS.any? { |kind| error.is_a?(kind) }
    notice = reload_notice(notice_id) unless db_error
    self.class.report(notice_id, error, account: notice&.account)
    raise error if db_error

    self.class.stop_failed!(notice, why: error.class.name) if notice
  end

  def reload_notice(notice_id)
    Crm::MeetingNotice.includes(meeting: :account).find_by(id: notice_id)
  rescue StandardError
    nil
  end

  # A 1 falhou: a 2 não sai (o `NoticeDispatchJob` cuida do aviso que não saiu). Cliente que parou ou reunião
  # cancelada: nada, nem alerta (também ao desistir). Sem wamid: ainda não saiu.
  def deliver(notice, attempt)
    first = Message.find_by(id: notice.message_id)
    return self.class.stop_failed!(notice, why: 'notice_message_missing') if first.nil?
    return if first.failed? || !self.class.wanted?(notice.meeting)
    return retry_or_give_up(notice, attempt) if first.source_id.blank?

    create_once!(notice, first)
  end

  # Passada a WINDOW não cria (a conferência de duplicata só cobre a WINDOW). Dentro dela, com o aviso travado.
  def create_once!(notice, first)
    return self.class.stop_failed!(notice, why: 'too_late') if Time.current > first.created_at + WINDOW

    notice.with_lock { create_stop!(notice, first) if still_wanted?(notice) && !self.class.stop_created?(notice.id, first) }
  end

  def retry_or_give_up(notice, attempt)
    return self.class.enqueue(notice, attempt: attempt + 1) if attempt < MAX_ATTEMPTS

    self.class.stop_failed!(notice, why: 'gave_up')
  end

  # Relidos dentro da trava (o `with_lock` relê o aviso): a conferência do cron pode tê-lo marcado, e o cliente pode
  # ter parado os avisos (ou a reunião ter sido cancelada) depois da 1.
  def still_wanted?(notice)
    notice.sent? && notice.error_code.nil? && self.class.wanted?(notice.meeting.reload)
  end

  def create_stop!(notice, first)
    conversation = first.conversation
    stop = Crm::BookingV2::Notices::Text.stop_message(manage_url(first), locale: Crm::BookingV2::Notices::Text.locale(notice.account))
    Crm::BookingV2::Notices::Delivery.new(
      decision: Crm::BookingV2::Notices::Route::Decision.new(mode: :session, conversation: conversation),
      inbox: conversation.inbox, contact: conversation.contact, sender: first.sender,
      content: stop[:content], rich_message: stop[:rich_message],
      marks: { crm_booking_notice_part: STOP_PART, crm_booking_notice_id: notice.id }
    ).perform
  end

  # Sem o botão na 1 não há link para o "Parar avisos": vira falha, com alerta, em vez de um botão quebrado.
  def manage_url(first)
    first.content_attributes.to_h.with_indifferent_access.dig(RichMessages::KEY, 'url').presence ||
      raise(ArgumentError, 'notice message without the manage button')
  end
end

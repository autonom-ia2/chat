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
# Idempotente: com o aviso travado (`with_lock`), não cria a 2 se já houver na conversa, depois da 1, mensagem com a
# marca `crm_booking_notice_part: 'stop'` + `crm_booking_notice_id` deste aviso. Mesma conversa, mesmo remetente e o
# mesmo `Notices::Delivery` da 1; o link é o do botão da 1 (`rich_message.url`) com `?stop_notices=1`.
#
# Falha (erro ao criar, ou desistência): o aviso continua `sent` (a 1 saiu), ganha `error_code: stop_part_failed` e o
# responsável é avisado UMA vez (`AgentAlert` `notice_stop_failed`). Nada é reenviado. A 2 marcada `failed` depois,
# pelo provedor: `NoticeDispatchJob#flag_undelivered_stop!`.
class Crm::BookingV2::NoticeStopPartJob < ApplicationJob
  queue_as :default

  WAIT = 10.seconds
  MAX_ATTEMPTS = 6
  STOP_PART = 'stop'.freeze
  STOP_PART_FAILED = 'stop_part_failed'.freeze
  # Mensagens depois da 1 que a conferência de duplicata olha: a 2 sai em até ~1 min, a conversa quase não anda.
  SCAN_LIMIT = 50

  # Enfileirar falhou (Redis fora): a 2 não vai sair, então o responsável fica sabendo.
  def self.enqueue(notice, attempt: 1)
    set(wait: WAIT).perform_later(notice.id, attempt)
  rescue StandardError => e
    stop_failed!(notice, e)
  end

  # Marca só aviso `sent` ainda sem marca: o alerta sai uma vez por aviso (e o `AgentAlert`, uma vez por reunião).
  def self.stop_failed!(notice, error = nil)
    Rails.logger.error("CRM booking notice #{notice.id} stop part failed: #{error ? error.class.name : 'gave_up'}")
    ChatwootExceptionTracker.new(error, account: notice.account).capture_exception if error
    changed = Crm::MeetingNotice.where(id: notice.id, status: :sent, error_code: nil)
                                .update_all(error_code: STOP_PART_FAILED, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    return unless changed.positive?

    Crm::BookingV2::Notices::AgentAlert.new(notice.meeting, 'notice_stop_failed', { kind: notice.kind, reason: STOP_PART_FAILED }).perform
  end

  def self.stop_part_of?(message, notice_id)
    mark = message.content_attributes.to_h.with_indifferent_access
    mark[:crm_booking_notice_part] == STOP_PART && mark[:crm_booking_notice_id] == notice_id
  end

  def perform(notice_id, attempt = 1)
    notice = Crm::MeetingNotice.includes(meeting: :account).find_by(id: notice_id)
    deliver(notice, attempt) if notice&.sent? && notice.error_code.nil?
  rescue StandardError => e
    self.class.stop_failed!(notice, e) if notice
  end

  private

  # A 1 sumiu ou falhou: a 2 não sai (o `NoticeDispatchJob` cuida do aviso que não saiu). Sem wamid: ainda não saiu.
  def deliver(notice, attempt)
    first = Message.find_by(id: notice.message_id)
    return if first.nil? || first.failed?
    return retry_or_give_up(notice, attempt) if first.source_id.blank?

    notice.with_lock { create_stop!(notice, first) unless already_created?(notice, first) }
  end

  def retry_or_give_up(notice, attempt)
    return self.class.enqueue(notice, attempt: attempt + 1) if attempt < MAX_ATTEMPTS

    self.class.stop_failed!(notice)
  end

  def already_created?(notice, first)
    first.conversation.messages.outgoing.where('messages.id > ?', first.id).order(:id).limit(SCAN_LIMIT)
         .any? { |message| self.class.stop_part_of?(message, notice.id) }
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

# "Criar os modelos na Meta" (#1272): o clique de um administrador marca os avisos como "enviando"
# (`NoticeTemplates::Requests#start!`) e enfileira este job, que cria na Meta, um por um, o modelo pronto de cada aviso
# (`NoticeTemplates::Creator`) e grava o fim de cada um na página: sem erro, a lista da caixa passa a responder por ele
# (em aprovação); com recusa da Meta (inclusive falta de permissão), "falhou" com o motivo em texto simples.
#
# Meta fora do ar: o ActiveJob tenta de novo (`retry_on`). Repetir não duplica: o `Creator` confere a caixa e a Meta pelo
# nome antes de criar. Esgotadas as tentativas, o que ainda estava "enviando" vira "falhou".
class Crm::BookingV2::NoticeTemplatesJob < ApplicationJob
  queue_as :default

  retry_on Crm::BookingV2::NoticeTemplates::Creator::Unreachable, wait: 15.seconds, attempts: 3 do |job, _error|
    job.give_up
  end

  def perform(page_id, inbox_id, kinds)
    page, inbox = records(page_id, inbox_id)
    return if page.blank? || inbox.blank?

    requests = Crm::BookingV2::NoticeTemplates::Requests.new(page: page, inbox: inbox)
    creator = Crm::BookingV2::NoticeTemplates::Creator.new(inbox: inbox)
    Array(kinds).each { |kind| create_one(creator, requests, inbox, kind) }
  end

  # Fim das tentativas com a Meta fora do ar: os avisos do pedido que ainda estão "enviando" viram "falhou".
  def give_up
    page, inbox = records(*arguments.first(2))
    return if page.blank? || inbox.blank?

    requests = Crm::BookingV2::NoticeTemplates::Requests.new(page: page, inbox: inbox)
    reason = Crm::BookingV2::NoticeTemplates::Catalog.text(inbox.account, 'meta_failed')
    Array(arguments.third).each do |kind|
      requests.finish!(kind, error: reason) if requests.states.dig(kind.to_s, 'state') == 'sending'
    end
  end

  private

  def records(page_id, inbox_id)
    page = Crm::AgentBookingProfile.find_by(id: page_id)
    inbox = page && Inbox.find_by(id: inbox_id, account_id: page.account_id)
    [page, inbox]
  end

  def create_one(creator, requests, inbox, kind)
    creator.create(kind)
    requests.finish!(kind)
  rescue Crm::BookingV2::NoticeTemplates::Creator::MetaError => e
    requests.finish!(kind, error: e.message)
  rescue Crm::BookingV2::NoticeTemplates::Creator::Unreachable
    raise
  rescue StandardError => e
    # Nada fica "enviando" para sempre: erro inesperado vai ao log (só a classe) e ao tracker, e o aviso fica "falhou".
    Rails.logger.error("[crm][booking_v2][notice_templates] job_failed inbox_id=#{inbox.id} error=#{e.class}")
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception unless e.is_a?(Crm::BookingV2::NoticeTemplates::Creator::Unsupported)
    requests.finish!(kind, error: Crm::BookingV2::NoticeTemplates::Catalog.text(inbox.account, 'meta_failed'))
  end
end

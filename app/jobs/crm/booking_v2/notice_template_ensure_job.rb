# Cria na Meta os 4 modelos v2 dos avisos do agendamento (#1524, épico #1585): ao marcar, horário mudou, 1 dia antes e
# 1 hora antes, com os botões "Ver meu horário" e "Parar avisos" (`Whatsapp::Templates::Finalidades::Agendamento`).
#
# Quem enfileira: o dono ligar o Aviso de serviço (`whatsapp_templates.consentimento_ligado`, initializer
# `crm_booking_notice_templates.rb`), publicar uma página ou trocar a caixa de avisos de uma página publicada
# (`Crm::BookingNoticeTemplateEnsure`). Fora da requisição, porque fala com a Meta.
#
# Só com o agendamento novo ligado na conta e o Aviso de serviço ligado (`WhatsappTemplateConsent.ativo?`). Caixas: as
# de avisos das páginas novas PUBLICADAS da conta que sejam WhatsApp oficial Cloud (`MetaClient.supported?`), sem
# repetir; com `inbox_id`, só ela, se cumprir isso. O `Garantir` não duplica pelo nome e não recria o que está em
# análise, então repetir o job é seguro.
#
# Cada resultado vai ao log (status e motivo, sem texto nem dado de cliente). Erro numa caixa ou finalidade vai ao
# tracker e não para as outras. Meta fora do ar em alguma: o job tenta de novo mais tarde (o que já foi criado volta
# "em análise" pela lista da caixa, sem falar com a Meta).
class Crm::BookingV2::NoticeTemplateEnsureJob < ApplicationJob
  class MetaFora < StandardError; end

  FINALIDADES = Whatsapp::Templates::Finalidades::Agendamento::POR_TIPO.values.freeze
  LOG = '[crm][booking_v2][notice_template_ensure]'.freeze

  queue_as :low

  retry_on MetaFora, wait: 5.minutes, attempts: 3 do |job, _error|
    Rails.logger.warn("#{LOG} desistiu account_id=#{job.arguments.first} motivo=meta_fora")
  end

  def perform(account_id, inbox_id = nil)
    account = Account.find_by(id: account_id)
    return unless account && autorizado?(account)

    resultados = inboxes(account, inbox_id).flat_map { |inbox| FINALIDADES.map { |finalidade| garantir(inbox, finalidade) } }
    raise MetaFora if resultados.any? { |resultado| resultado.to_h[:motivo] == 'meta_fora' }
  end

  private

  def autorizado?(account)
    Crm::Config.booking_v2_enabled?(account) && WhatsappTemplateConsent.ativo?(account, :utility)
  end

  def inboxes(account, inbox_id)
    pages = account.crm_agent_booking_profiles.new_pages.enabled
    pages = pages.where(notice_inbox_id: inbox_id) if inbox_id.present?
    Inbox.where(account_id: account.id, id: pages.select(:notice_inbox_id)).includes(:channel).order(:id)
         .select { |inbox| Whatsapp::Templates::MetaClient.supported?(inbox) }
  end

  def garantir(inbox, finalidade)
    resultado = Whatsapp::Templates::Garantir.call(inbox: inbox, finalidade: finalidade, criar: true)
    Rails.logger.info("#{LOG} account_id=#{inbox.account_id} inbox_id=#{inbox.id} finalidade=#{finalidade} " \
                      "status=#{resultado[:status]} motivo=#{resultado[:motivo] || '-'}")
    resultado
  rescue StandardError => e
    Rails.logger.error("#{LOG} erro account_id=#{inbox.account_id} inbox_id=#{inbox.id} finalidade=#{finalidade} #{e.class.name}")
    ChatwootExceptionTracker.new(e, account: inbox.account).capture_exception
    nil
  end
end

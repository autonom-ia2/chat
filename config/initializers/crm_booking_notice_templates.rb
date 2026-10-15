# Agendamento (#1524, épico #1585): quando o dono liga o Aviso de serviço na tela de Modelos (#1586), cria os 4 modelos
# v2 dos avisos nas caixas oficiais das páginas publicadas. O evento sai depois do commit da autorização
# (`WhatsappTemplateConsent::EVENTO_LIGADO`, escrito aqui como texto para não carregar o modelo no boot); o job fala
# com a Meta fora da requisição.
#
# Contrato do #1603: o assinante nunca derruba quem publica. Erro ao enfileirar fica no log (só a classe) e no tracker.
ActiveSupport::Notifications.subscribe('whatsapp_templates.consentimento_ligado') do |*, payload|
  next unless payload[:marca].to_s == 'utility'
  next if payload[:account_id].blank?

  Crm::BookingV2::NoticeTemplateEnsureJob.perform_later(payload[:account_id])
rescue StandardError => e
  Rails.logger.error("[crm][booking_v2][notice_template_ensure] nao_enfileirado account_id=#{payload[:account_id]} #{e.class.name}")
  ChatwootExceptionTracker.new(e).capture_exception
end

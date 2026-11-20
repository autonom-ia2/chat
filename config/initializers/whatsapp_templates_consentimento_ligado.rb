# Quando o dono liga o Aviso de serviço na tela de Modelos (#1586), quem tem modelos fixos pede os seus à Meta:
# - Agendamento (#1524, épico #1585): os 4 modelos v2 dos avisos, nas caixas oficiais das páginas publicadas
#   (Crm::BookingV2::NoticeTemplateEnsureJob);
# - cotação da renovação do seguro (#3055): os 2 modelos, na caixa escolhida em Ajustar renovações
#   (Carteira::Cotacao::ModelosJob).
# O evento sai depois do commit da autorização (`WhatsappTemplateConsent::EVENTO_LIGADO`, escrito aqui como texto para
# não carregar o modelo no boot); cada job reconfere o que precisa e fala com a Meta fora da requisição.
#
# Um assinante só, com os jobs em lista: quem precisar reagir ao mesmo evento entra nela. Contrato do #1603: o assinante
# nunca derruba quem publica. Erro ao enfileirar um job fica no log (só a classe) e no tracker, e não impede o outro.
ActiveSupport::Notifications.subscribe('whatsapp_templates.consentimento_ligado') do |*, payload|
  next unless payload[:marca].to_s == 'utility'
  next if payload[:account_id].blank?

  [Crm::BookingV2::NoticeTemplateEnsureJob, Carteira::Cotacao::ModelosJob].each do |job|
    job.perform_later(payload[:account_id])
  rescue StandardError => e
    Rails.logger.error("[whatsapp][templates][consentimento_ligado] nao_enfileirado job=#{job.name} " \
                       "account_id=#{payload[:account_id]} #{e.class.name}")
    ChatwootExceptionTracker.new(e).capture_exception
  end
end

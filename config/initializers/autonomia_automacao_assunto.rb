# G71 (#2883): a decisão da IA de assunto (Crm::Subjects::IdentifyJob::EVENTO) acorda o "extrair" da Automação livre que
# espera o card da conversa nascer (Autonomia::Automacao::EsperaDoAssunto). O nome do evento fica escrito aqui como texto
# para não carregar o job no boot. Assinado uma vez, no boot; as constantes são lidas na hora do evento, então o
# recarregamento do desenvolvimento não duplica o assinante. O erro fica no log dentro do EsperaDoAssunto.
Rails.application.config.after_initialize do
  ActiveSupport::Notifications.subscribe('crm.subject.decided') do |*, payload|
    Autonomia::Automacao::EsperaDoAssunto.decidido(payload[:conversation_id])
  end
end

# frozen_string_literal: true

# chat#1330 (épico #1320) — Modelos do WhatsApp: o sync da caixa passa a pedir os campos que a tela de Modelos e o
# agendamento leem (`fields=`, inclusive `rejected_reason`). Prepend com nome próprio do fork; o arquivo do Chatwoot e o
# módulo de voz do enterprise (`Enterprise::Whatsapp::Providers::WhatsappCloudService`, que não mexe no sync) ficam
# intactos. Este prepend roda depois do `prepend_mod_with` da classe, então fica à frente do módulo de voz na cadeia.
Rails.application.config.to_prepare do
  prepend_once = lambda do |klass, mod|
    klass.prepend(mod) unless klass.ancestors.include?(mod)
  end

  prepend_once.call(Whatsapp::Providers::WhatsappCloudService, Whatsapp::Templates::SyncFields)
  # chat#1382: a conferência do disparo pergunta ao envio se ele vai achar o modelo na lista da caixa.
  prepend_once.call(Whatsapp::TemplateProcessorService, Whatsapp::Templates::ProcessorLookup)
  # chat#1334: o envio monta os componentes dos formatos novos (oferta, carrossel, Flow, catálogo) quando a campanha os traz.
  prepend_once.call(Whatsapp::TemplateProcessorService, Whatsapp::Templates::SendComponents)
  prepend_once.call(Whatsapp::TemplateParameterConverterService, Whatsapp::Templates::ForkParamKeys)
  # chat#1337: aviso da Meta sobre modelo (situação, qualidade, tipo) vai para o job do fork, com assinatura obrigatória.
  prepend_once.call(Webhooks::WhatsappController, Whatsapp::Templates::WebhookEntry)
end

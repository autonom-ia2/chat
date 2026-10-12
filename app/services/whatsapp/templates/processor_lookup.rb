# O envio de modelo (`Whatsapp::TemplateProcessorService`, do Chatwoot) procura o modelo SÓ na lista guardada da caixa e,
# se não acha, devolve `nil` como parâmetros: o modelo sai sem variáveis e a Meta recusa cada envio (#1382, auditoria A1).
# Este módulo, prependido pelo `config/initializers/whatsapp_templates.rb`, expõe a mesma busca do envio para a
# conferência do disparo da campanha (`CampaignPauses::WhatsappDispatchGate`) parar a campanha antes do primeiro envio
# quando o envio não vai achar o modelo. O envio em si fica como o Chatwoot fez.
module Whatsapp::Templates::ProcessorLookup
  # O modelo que o envio vai usar está na lista da caixa (mesmo nome, idioma e aprovado)?
  def template_in_list?
    template_params.present? && find_template.present?
  end
end

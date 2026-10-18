# O ponto único que grava a foto do envio (#1717): prependido em `Whatsapp::TemplateProcessorService` (do Chatwoot) pelo
# `config/initializers/whatsapp_templates.rb`, por fora do `SendComponents`. O arquivo do Chatwoot fica intacto.
#
# Todo envio de modelo com mensagem na conversa passa pelo processamento do modelo (`Whatsapp::SendOnWhatsappService`):
# o modelo mandado da conversa, o fora da janela (`EnvioForaDaJanela` → `MessageSender` do Followup) e os avisos do
# agendamento (`Crm::BookingV2`). Ali, logo antes de a Meta receber o pedido, a foto (`Whatsapp::Templates::Enviado`)
# entra em `additional_attributes.template_params.enviado`, sem coluna nova e sem mexer no que vai à Meta.
#
# A campanha processa o modelo sem mensagem (ela só nasce depois, no `CampaignJourney::SentMessageRecorder`): quem grava
# lá pede `foto_do_envio` com os mesmos parâmetros da pessoa.
#
# A foto nunca atrapalha o envio: se algo falhar ao montá-la, o envio segue sem ela e só a classe do erro vai ao log.
module Whatsapp::Templates::FotoDoEnvio
  # A foto do que este envio leva, ou nil quando o envio não acha o modelo na lista da caixa.
  def foto_do_envio(catalogo: :consultar, perfil: false)
    template = find_template if template_params.is_a?(Hash)
    return if template.blank?

    normalizado = Whatsapp::TemplateParameterConverterService.new(template_params.deep_dup, template).normalize_to_enhanced
    Whatsapp::Templates::Enviado.montar(template: template, processed: normalizado['processed_params'], inbox: channel.inbox,
                                        catalogo: catalogo, perfil: perfil)
  rescue StandardError => e
    Rails.logger.error("[whatsapp][templates][enviado] foto_nao_montada error=#{e.class}")
    nil
  end

  private

  # `super` troca `@template_params` pelos componentes do pedido: o que foi enviado é lido antes.
  def process_enhanced_template_params(template, processed_params = nil)
    enviados = processed_params || template_params['processed_params']
    componentes = super
    gravar_foto(template, enviados) if message&.persisted?
    componentes
  end

  def gravar_foto(template, enviados)
    foto = Whatsapp::Templates::Enviado.montar(template: template, processed: enviados, inbox: channel.inbox)
    atributos = message.additional_attributes.to_h
    modelo = atributos['template_params'].is_a?(Hash) ? atributos['template_params'] : {}
    # Sem callbacks: a foto não é edição da mensagem; o `update!` do envio (source_id ou falha) avisa a tela.
    message.update_columns(additional_attributes: atributos.merge('template_params' => modelo.merge('enviado' => foto))) # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("[whatsapp][templates][enviado] foto_nao_gravada message_id=#{message.id} error=#{e.class}")
  end
end

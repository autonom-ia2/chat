# Botão "Ver meu horário" das mensagens do agendamento (#1517): o link de gestão vai num botão de link
# (`RichMessages::Types::LinkButton`, #1473) em vez de cru no texto. Este é o único lugar que decide se ele sai.
#
# Sai só quando a mensagem vai como texto pela sessão (`mode: :session`), não é o WhatsApp Híbrido (o plano B leva só
# texto) e `RichMessages.delivery_mode` responde `:native` para a conversa onde a mensagem vai ser criada (WhatsApp
# oficial `whatsapp_cloud` com a janela aberta). Sem conversa (o `Delivery` abriria uma nova) a janela é desconhecida
# e o botão não sai. WAHA, 360dialog, canal API e modelo da Meta seguem só em texto.
class Crm::BookingV2::Notices::Button
  TYPE = 'link_button'.freeze

  def self.allowed?(decision, inbox)
    decision.mode == :session && decision.via != Crm::BookingV2::Notices::Route::HYBRID_WEB &&
      RichMessages.delivery_mode(inbox: inbox, type: TYPE, conversation: decision.conversation) == :native
  end

  def self.rich_message(url, locale:)
    { 'type' => TYPE, 'label' => I18n.t('crm.booking_v2.notices.button_label', locale: locale), 'url' => url }
  end
end

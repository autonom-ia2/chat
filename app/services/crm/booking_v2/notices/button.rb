# Botão "Ver meu horário" das mensagens do agendamento (#1517): o link de gestão vai num botão de link
# (`RichMessages::Types::LinkButton`, #1473) em vez de cru no texto. Este é o único lugar que decide se ele sai.
#
# Sai só quando a mensagem vai como texto pela sessão (`mode: :session`), não é o WhatsApp Híbrido (o plano B leva só
# texto) e `RichMessages.delivery_mode` responde `:native` para a conversa onde a mensagem vai ser criada (WhatsApp
# oficial `whatsapp_cloud` com a janela aberta). Sem conversa (o `Delivery` abriria uma nova) a janela é desconhecida
# e o botão não sai. WAHA, 360dialog, canal API e modelo da Meta seguem só em texto.
#
# Rótulo por tipo de mensagem: `:notice` (reunião já marcada) "Ver meu horário"; `:invite` (convite para marcar, como o
# "Testar no meu WhatsApp") "Escolher horário"; `:stop` (#1562, a mensagem separada logo depois do aviso) "Parar avisos".
#
# `fits?`: o corpo FINAL que vai junto do botão (no aviso, sem a linha de parar desde #1562; no teste, com o
# prefixo) cabe no limite do `cta_url` (`LinkButton::BODY_MAX`). Não cabendo, quem chama manda só texto, com a linha
# do link: o `SendGuard` recusaria o botão e a mensagem ficaria `failed`, sem link nenhum.
#
# Envio assíncrono: a mensagem é criada aqui e sai depois (`SendReplyJob`). Se o provedor ou o `SendGuard` a marcar
# `failed`, o `NoticeDispatchJob#fail_undelivered!` passa o aviso a `failed: delivery_failed` e avisa o responsável.
class Crm::BookingV2::Notices::Button
  TYPE = 'link_button'.freeze
  LABELS = { notice: 'crm.booking_v2.notices.button_label', invite: 'crm.booking_v2.invite.button_label',
             stop: 'crm.booking_v2.notices.stop_button_label' }.freeze

  def self.allowed?(decision, inbox)
    decision.mode == :session && decision.via != Crm::BookingV2::Notices::Route::HYBRID_WEB &&
      RichMessages.delivery_mode(inbox: inbox, type: TYPE, conversation: decision.conversation) == :native
  end

  def self.fits?(body)
    body.length <= RichMessages::Types::LinkButton::BODY_MAX
  end

  def self.rich_message(url, kind:, locale:)
    { 'type' => TYPE, 'label' => I18n.t(LABELS.fetch(kind), locale: locale), 'url' => url }
  end
end

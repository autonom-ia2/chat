# O aviso "N seguros entraram em renovação hoje" (E5, #2898) dentro do model de notificação do Chatwoot. O que esse
# tipo tem de próprio fica aqui: o título, o texto e a entrega só no painel (push e e-mail são feitos para conversa). O
# Notification só ganha o tipo na lista e o `prepend` deste módulo; para todo outro tipo, vale o que ele já fazia.
#
# O ator é o Carteira::RenovacaoConfig da conta, e o total do dia vem em `meta['quantos']` (Carteira::Aviso).
module Carteira::NotificacaoDaRenovacao
  def push_message_title
    return super unless carteira_renovacao?

    I18n.t('notifications.notification_title.carteira_renovacao')
  end

  def push_message_body
    return super unless carteira_renovacao?

    I18n.t('notifications.carteira_renovacao.entraram', count: meta.to_h['quantos'].to_i)
  end

  private

  def process_notification_delivery
    return super unless carteira_renovacao?

    Notification::RemoveDuplicateNotificationJob.perform_later(self)
  end
end

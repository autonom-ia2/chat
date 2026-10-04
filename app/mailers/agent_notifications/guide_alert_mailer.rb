# O e-mail do aviso urgente do Guia (#935): o texto do aviso e o caminho para abrir o Guia.
#
# O texto já sai sem dado pessoal (`TextoDoAviso`): o nome da vigia e os números medidos.
class AgentNotifications::GuideAlertMailer < ApplicationMailer
  def guide_alert(aviso, agent)
    return unless smtp_config_set_or_development?

    @agent = agent
    @aviso = aviso
    @action_url = ::Autonomia::Guide::Aviso.link_no_painel(aviso.account_id)
    send_mail_with_liquid(to: @agent.email, subject: I18n.t('notifications.notification_title.guide_alert')) and return
  end

  private

  def liquid_droppables
    super.merge({ user: @agent })
  end

  def liquid_locals
    super.merge({ texto: @aviso.texto, abrir: I18n.t('autonomia.guide.avisos.abrir_no_guia') })
  end
end

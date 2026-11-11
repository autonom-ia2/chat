# #2858 F7: o alerta à equipe quando o custo do mês das consultas Premium (BigDataCorp) passa de 80% do orçamento
# (`Autonomia::FerramentasProntas::Premium::Orcamento`). Vai ao administrador da instalação
# (`CHATWOOT_INSTANCE_ADMIN_EMAIL`); sem ele, fica só o log `[autonomia][premium] orcamento_80`.
class AdministratorNotifications::PremiumMailer < AdministratorNotifications::BaseMailer
  def orcamento_do_mes
    return if instance_admin_email.blank?

    meta = { 'gasto' => params[:gasto], 'orcamento' => params[:orcamento], 'mes' => params[:mes],
             'instance_url' => ENV.fetch('FRONTEND_URL', '') }
    send_notification("Consultas Premium: o custo de #{params[:mes]} passou de 80% do orçamento", to: instance_admin_email, meta: meta)
  end

  private

  def instance_admin_email
    GlobalConfig.get('CHATWOOT_INSTANCE_ADMIN_EMAIL')['CHATWOOT_INSTANCE_ADMIN_EMAIL']
  end
end

# O aviso de clique da página (#1011) chegou DEPOIS da mensagem com #TOKEN (rede móvel
# lenta, beacon atrasado): a mensagem já passou pelo atribuidor sem achar o clique. Este
# job, enfileirado logo depois de gravar o aviso, procura essa mensagem e liga a conversa.
# Sem mensagem, não faz nada: o clique fica esperando a mensagem normalmente.
class Ctwa::LateClickReconcileJob < ApplicationJob
  queue_as :low

  def perform(click_id)
    click = Ctwa::TrackedLinkClick.active.includes(:tracked_link).find_by(id: click_id)
    return if click.blank?

    Ctwa::TrackedLinkAttributor.attribute_late_click!(click)
  end
end

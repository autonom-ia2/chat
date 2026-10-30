# Título gravado do lembrete de Atender (#1498). A equipe o lê no card e ele não é reescrito depois. Fora de uma
# requisição o pacote da conta não vale (#1550), então o job entra nele aqui (#2076): a corretora lê "parcela" onde o
# texto base diz "pagamento".
module Crm::FollowUps::ServiceReminderTitle
  def self.for(account, kind)
    Autonomia::Segmentos::Pacotes.with(account) do
      I18n.with_locale(account.locale) { I18n.t("crm.service_reminders.#{kind}") }
    end
  end
end

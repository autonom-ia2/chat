# Os valores da reunião que a receita lê (Valores): o início da reunião do gatilho (G12) e se há reunião marcada e
# ainda por vir, não cancelada nem remarcada para outra (`card.tem_reuniao_marcada`, G32; `contato.tem_reuniao_marcada`,
# #2710).
#
# No contato, só contam os cards que quem ligou a automação vê, pela mesma pergunta do resto do CRM
# (Crm::CardPolicy::Scope): reunião em card de funil que ele não vê não decide o ramo (parecer do Funções no #2703).
# Sem pessoa, nada é visto.
module Autonomia::Automacao::ValoresDaReuniao
  module_function

  # "10/11/2026 às 09:00", no fuso e no idioma da reunião e da conta: o mesmo do convite que o cliente recebeu.
  def inicio(reuniao)
    inicio = reuniao.starts_at.in_time_zone(ActiveSupport::TimeZone[reuniao.timezone.to_s] || Time.zone)
    formato = I18n.t('autonomia.automacao.valores.inicio_da_reuniao', locale: reuniao.account.locale.presence || I18n.default_locale)
    inicio.strftime(formato)
  end

  def marcada_no_card?(card) = card.account.crm_meetings.upcoming.exists?(card_id: card.id)

  def marcada_no_contato?(contato, account_user)
    return false if account_user.nil?

    acesso = { user: account_user.user, account: contato.account, account_user: account_user }
    cards = Pundit.policy_scope!(acesso, ::Crm::Card).where(account_id: contato.account_id, contact_id: contato.id)
    contato.account.crm_meetings.upcoming.exists?(card_id: cards.select(:id))
  end
end

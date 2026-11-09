# Os valores da reunião que a receita lê (Valores): o início da reunião do gatilho (G12) e se há reunião marcada e
# ainda por vir, não cancelada nem remarcada para outra (`card.tem_reuniao_marcada`, G32; `contato.tem_reuniao_marcada`,
# #2710). G59: se uma reunião do contato aconteceu durante o "esperar até" (`contato.reuniao_atendida`).
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

    contato.account.crm_meetings.upcoming.exists?(card_id: cards_que_ve(contato, account_user).select(:id))
  end

  # G59 (exemplo 6, passo 8: "Atendida: no dia seguinte..."): o primeiro "Aconteceu" de uma reunião do contato caiu
  # dentro da janela da espera (`espera`, como na Resposta). Vale a reunião de qualquer card do contato que quem ligou vê:
  # a página de agendamento pode pôr a reunião em outro card do mesmo contato. "Não compareceu", salvar as anotações de
  # novo e voltar para "Aconteceu" não contam (first_held, G56). Sem contato ou sem quem ligou, nunca aconteceu.
  def atendida_no_contato?(contato, espera, quem)
    account_user = contato && quem && contato.account.account_users.find_by(user_id: quem.id)
    return false if account_user.nil?

    atendidas = ::Crm::Activity.where(account_id: contato.account_id, event_type: 'meeting_outcome_recorded',
                                      card_id: cards_que_ve(contato, account_user).select(:id))
                               .where("crm_activities.payload ->> 'first_held' = 'true'")
                               .where('crm_activities.created_at > ?', espera.begin)
    (espera.end ? atendidas.where('crm_activities.created_at <= ?', espera.end) : atendidas).exists?
  end

  # Os cards do contato que quem ligou vê, pela mesma pergunta do resto do CRM (Crm::CardPolicy::Scope).
  def cards_que_ve(contato, account_user)
    acesso = { user: account_user.user, account: contato.account, account_user: account_user }
    Pundit.policy_scope!(acesso, ::Crm::Card).where(account_id: contato.account_id, contact_id: contato.id)
  end
end

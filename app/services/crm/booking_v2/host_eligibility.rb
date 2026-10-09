# Quem pode ser o responsável (host) de uma página ou de um link individual de agendamento.
#
# Não depende de caixa de e-mail: é uma pessoa da conta. Quem tem função personalizada precisa ter alguma chave de
# CRM ou de agendamento; quem não tem função (agente comum ou administrador) sempre pode.
#
# Avaliado ao SERVIR a página: se o responsável saiu da conta ou perdeu a função, a página se comporta como pausada
# (e aparece no relatório de atenção do admin) em vez de aceitar reservas que ninguém vai atender.
class Crm::BookingV2::HostEligibility
  CUSTOM_ROLE_KEYS = %w[
    crm_view crm_manage_cards crm_move_cards crm_manage_pipelines crm_admin
    agendamento_view agendamento_manage
  ].freeze

  def self.eligible?(account:, user:)
    return false if account.blank? || user.blank?

    account_user = account.account_users.find_by(user_id: user.id)
    return false if account_user.blank?
    return true if account_user.custom_role_id.blank?

    account_user.custom_role&.permissions.to_a.intersect?(CUSTOM_ROLE_KEYS)
  end
end

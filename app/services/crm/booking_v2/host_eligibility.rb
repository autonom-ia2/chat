# Quem pode ser o responsável (host) de uma página ou de um link individual de agendamento.
#
# Não depende de caixa de e-mail: é uma pessoa da conta que consegue VER o card que a reserva cria. Mesmo critério
# do `Enterprise::Crm::CardPolicy#index?` (`CrmPermissions#crm_permission?('crm_view')`): administrador e agente
# sem função personalizada sempre podem; com função, só se ela tiver `crm_view` ou `crm_admin`. As chaves
# `agendamento_*` sozinhas NÃO bastam: dão acesso às páginas, não aos cards. Membro de integração (token de API)
# nunca atende reunião.
#
# Avaliado ao SERVIR a página: se o responsável saiu da conta ou perdeu a função, a página se comporta como pausada
# (e aparece no relatório de atenção do admin) em vez de aceitar reservas que ninguém vai atender.
class Crm::BookingV2::HostEligibility
  CUSTOM_ROLE_KEYS = %w[crm_view crm_admin].freeze

  def self.eligible?(account:, user:)
    return false if account.blank? || user.blank?

    account_user = account.account_users.find_by(user_id: user.id)
    account_user.present? && !account_user.integration? && sees_cards?(account_user)
  end

  def self.sees_cards?(account_user)
    return true if account_user.administrator? || account_user.custom_role_id.blank?

    account_user.custom_role&.permissions.to_a.intersect?(CUSTOM_ROLE_KEYS)
  end
  private_class_method :sees_cards?
end

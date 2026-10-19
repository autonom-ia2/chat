# Quem não vê a base de contatos (#1849, decisão D7) recebe no card só nome, telefone e e-mail do contato: sem
# empresa, campos, etiquetas do contato nem selo de cliente. Sem usuário e vínculo com a conta, vai o enxuto.
class Crm::Cards::ContactReading
  def self.full?(user:, account_user:)
    return false if user.blank? || account_user.blank?

    ContactPolicy.new({ user: user, account: account_user.account, account_user: account_user }, Contact).index?
  end
end

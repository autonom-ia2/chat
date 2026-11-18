# A chave da cotação da renovação (E8, #2901). Cada cotação no Agger consome consulta paga e pode virar mensagem ao
# cliente, então ela só acontece na conta que o Super Admin liberou. A chave nasce desligada em toda conta, e pode ser
# vendida como upgrade (decisão 5 do desenho).
#
# Mora em `accounts.internal_attributes` (jsonb interno, que a pessoa da conta não edita), no molde da chave da leitura
# de PDF (Carteira::Leitor::Liberado): sem bit de flag e sem migration. É só a chave: o portão inteiro (carteira, chave e
# escolha da conta) é Carteira::Cotacao.aberta?.
module Carteira::Cotacao::Liberada
  ATRIBUTO = 'carteira_cotacao_renovacao_liberada'.freeze
  BOOLEANO = ActiveModel::Type::Boolean.new

  # Sempre true ou false, nunca nil.
  def self.para?(account)
    return false if account.blank?

    BOOLEANO.cast(account.internal_attributes.to_h[ATRIBUTO]) || false
  end

  def self.ligar!(account)
    gravar!(account, true)
  end

  def self.desligar!(account)
    gravar!(account, false)
  end

  def self.gravar!(account, ligada)
    account.internal_attributes = account.internal_attributes.to_h.merge(ATRIBUTO => ligada)
    account.save!
    account
  end
  private_class_method :gravar!
end

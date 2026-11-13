# A chave da leitura de apólice por PDF (E6, #2899). Cada leitura é uma chamada paga ao modelo, então ela só acontece
# na conta que o Super Admin liberou. A chave nasce desligada em toda conta.
#
# Mora em `accounts.internal_attributes` (jsonb interno, que a pessoa da conta não edita), no molde da chave da Cotação
# (Autonomia::Insurance::Config): sem bit de flag e sem migration. É só a chave da leitura: quem tem a carteira
# continua sendo Carteira::Acesso.
module Carteira::Leitor::Liberado
  ATRIBUTO = 'carteira_leitura_de_pdf_liberada'.freeze
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

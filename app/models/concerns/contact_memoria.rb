# Memória das IAs (#1601): apagar o contato apaga a memória dele na mesma transação (Crm::Memoria::Apagar).
module ContactMemoria
  extend ActiveSupport::Concern

  included do
    before_destroy :apagar_memoria_ia
  end

  private

  def apagar_memoria_ia
    Crm::Memoria::Apagar.contato!(self)
  end
end

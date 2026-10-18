# Memória das IAs (#1601): o campo do contato editado à mão vira correção da pessoa (A14). Apagar o contato apaga os
# fatos dele pela FK em cascata.
module ContactMemoria
  extend ActiveSupport::Concern

  included do
    # A cópia de atributos da mescla (Crm::Memoria::Correcao.sem_correcao) não é correção de pessoa.
    attr_accessor :memoria_sem_correcao

    after_update_commit :memoria_campos_editados, if: :saved_change_to_custom_attributes?
  end

  private

  # O fato do contato não precisa de card: o "card" aqui só carrega a conta e o contato.
  def memoria_campos_editados
    dono = Crm::Card.new(account: account, contact_id: id)
    Crm::Memoria::Correcao.dos_campos!(self, saved_change_to_custom_attributes, 'contact_attribute', card: dono)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end
end

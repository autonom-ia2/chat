# Memória das IAs (#1601), no card: o campo editado à mão vira correção da pessoa (A14), e o card encerrado ou reaberto
# entra ou sai da memória do cliente (D6). Depois do commit; uma falha aqui não desfaz a edição do card.
module Crm::CardMemoria
  extend ActiveSupport::Concern

  included do
    # A gravação da IA no campo (Crm::Memoria::Correcao.sem_correcao) não é correção de pessoa.
    attr_accessor :memoria_sem_correcao

    after_update_commit :memoria_campos_editados, if: :saved_change_to_custom_attributes?
    after_update_commit :memoria_status_mudou, if: :saved_change_to_status?
  end

  private

  def memoria_campos_editados
    Crm::Memoria::Correcao.dos_campos!(self, saved_change_to_custom_attributes, 'card_attribute', card: self)
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: account).capture_exception
  end

  def memoria_status_mudou
    Crm::Memoria::FechamentoJob.perform_later(id) if contact_id.present? && Crm::Memoria.ligada?(account)
  end
end

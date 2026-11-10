# O campo personalizado do card do tipo "contato" (decisão 16 da Automação, ex. 11): guarda o id de um contato da conta
# ("indicado por Maria"), que o passo "em outro registro" usa para achar a pessoa ligada. Vale para todo caminho que grava
# o card (a tela, a API, o upsert, um passo da automação): o número que chega como texto ("12") vira número, e o contato
# que não é da conta é recusado, nunca guardado. Vazio apaga.
#
# Só o campo que mudou é conferido: o contato apagado depois de gravado não trava a edição dos outros campos do card (o
# "em outro registro" registra que ele sumiu). Simétrico ao tipo pessoa da equipe (G62, Crm::CardCampoPessoa).
module Crm::CardCampoContato
  extend ActiveSupport::Concern

  included do
    before_validation :normalizar_campos_contato, if: :will_save_change_to_custom_attributes?
    validate :campos_contato_da_conta, if: :will_save_change_to_custom_attributes?
  end

  private

  def chaves_de_contato
    account&.custom_attribute_definitions&.where(attribute_model: :card_attribute, attribute_display_type: :contato)
           &.pluck(:attribute_key).to_a
  end

  def campos_contato_preenchidos(chaves) = custom_attributes.to_h.slice(*chaves).reject { |_, valor| valor.blank? }

  def normalizar_campos_contato
    lidos = campos_contato_preenchidos(chaves_de_contato).transform_values { |valor| Integer(valor.to_s, 10, exception: false) || valor }
    self.custom_attributes = custom_attributes.to_h.merge(lidos) if lidos.present?
  end

  def campos_contato_da_conta
    antes = custom_attributes_in_database.to_h
    mudados = campos_contato_preenchidos(chaves_de_contato).reject { |chave, valor| antes[chave].to_s == valor.to_s }
    return if mudados.empty?

    da_conta = Contact.where(account_id: account_id, id: mudados.values.grep(Integer)).pluck(:id)
    mudados.each do |chave, valor|
      errors.add(:custom_attributes, I18n.t('errors.crm.contato_de_fora', chave: chave)) unless da_conta.include?(valor)
    end
  end
end

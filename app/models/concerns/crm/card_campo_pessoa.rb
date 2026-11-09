# O campo personalizado do card do tipo "pessoa da equipe" (G62, #2829): guarda o id de um usuário da conta, como o
# `owner_id`. Vale para todo caminho que grava o card (a tela, a API, o upsert, um passo da automação): o número que
# chega como texto ("12") vira número, e a pessoa que não é da conta é recusada, nunca guardada. Vazio apaga.
module Crm::CardCampoPessoa
  extend ActiveSupport::Concern

  included do
    before_validation :normalizar_campos_pessoa, if: :will_save_change_to_custom_attributes?
    validate :campos_pessoa_da_conta, if: :will_save_change_to_custom_attributes?
  end

  private

  def chaves_de_pessoa
    @chaves_de_pessoa ||= account&.custom_attribute_definitions&.where(attribute_model: :card_attribute, attribute_display_type: :pessoa)
                                 &.pluck(:attribute_key).to_a
  end

  def campos_pessoa_preenchidos = custom_attributes.to_h.slice(*chaves_de_pessoa).reject { |_, valor| valor.blank? }

  def normalizar_campos_pessoa
    lidos = campos_pessoa_preenchidos.transform_values { |valor| Integer(valor.to_s, 10, exception: false) || valor }
    self.custom_attributes = custom_attributes.to_h.merge(lidos) if lidos.present?
  end

  def campos_pessoa_da_conta
    preenchidos = campos_pessoa_preenchidos
    return if preenchidos.empty?

    da_conta = AccountUser.where(account_id: account_id, user_id: preenchidos.values.select { |valor| valor.is_a?(Integer) }).pluck(:user_id)
    preenchidos.each do |chave, valor|
      errors.add(:custom_attributes, I18n.t('errors.crm.pessoa_de_fora', chave: chave)) unless da_conta.include?(valor)
    end
  end
end

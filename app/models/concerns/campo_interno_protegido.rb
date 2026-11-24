# #3176 — a definição de uma chave interna (Relationships::ChavesInternas: as da WAHA e as de controle da Prospecção)
# não é apagada e não troca de chave, de tipo nem de modelo. Sem a definição `waha_whatsapp_chat_id` a busca da WAHA
# deixa de filtrar e pode achar o contato errado; com outro tipo, o valor gravado deixa de casar com o filtro. O nome e o
# "Para que serve" continuam editáveis. Vale para toda porta (tela, Guia, MCP, API): quem recusa é o modelo, e o
# controller devolve o motivo com 422 (RecordInvalid no update, `destroy` falso no apagar).
#
# Olha a chave dos dois lados: trocar `attribute_key` de uma interna é recusado, e trocar a chave de uma definição comum
# para a de uma interna também (ela passaria a valer como interna sem ser a da WAHA ou da Prospecção). Criar com a chave
# de uma interna continua possível, como a WAHA faz.
#
# A conta apagada leva as definições junto (`dependent: :destroy_async`): o job roda depois que a conta saiu do banco,
# e aí a definição não tem mais conta para proteger.
module CampoInternoProtegido
  extend ActiveSupport::Concern

  MUDANCAS = %w[attribute_key attribute_display_type attribute_model].freeze

  included do
    validate :campo_interno_ao_mudar, on: :update
    before_destroy :campo_interno_ao_apagar, prepend: true
  end

  private

  def campo_interno_ao_mudar
    era_interna = Relationships::ChavesInternas.interna?(attribute_key_in_database)
    vira_interna = will_save_change_to_attribute_key? && Relationships::ChavesInternas.interna?(attribute_key)
    return unless vira_interna || (era_interna && MUDANCAS.any? { |campo| will_save_change_to_attribute?(campo) })

    errors.add(:base, I18n.t('errors.custom_attribute_definition.campo_interno'))
  end

  def campo_interno_ao_apagar
    return if account.nil? || !Relationships::ChavesInternas.interna?(attribute_key_in_database)

    errors.add(:base, I18n.t('errors.custom_attribute_definition.campo_interno'))
    throw :abort
  end
end

# O campo do card do tipo contato (decisão 16) que uma automação ligada usa para achar o contato ligado ("em outro
# registro", ex. 11) não troca de tipo, de chave ou de modelo, nem é apagado, enquanto ela estiver ligada. Trocar o tipo
# faria o número guardado (um pedido, um protocolo) virar id de contato, e a mensagem iria a outro cliente. A rodada
# confere de novo (PassoEmOutroRegistro, `campo_nao_e_contato`); aqui a pessoa fica sabendo antes, com o nome dela.
module CampoContatoEmUso
  extend ActiveSupport::Concern

  MUDANCAS = %w[attribute_display_type attribute_key attribute_model].freeze

  included do
    validate :contato_em_uso_ao_mudar, on: :update
    before_destroy :contato_em_uso_ao_apagar, prepend: true
  end

  private

  def contato_em_uso_ao_mudar
    return unless MUDANCAS.any? { |campo| will_save_change_to_attribute?(campo) }

    avisar_contato_em_uso
  end

  def contato_em_uso_ao_apagar
    throw :abort if avisar_contato_em_uso
  end

  # Adiciona o erro e devolve true quando o campo, como está no banco, é lido por automação ligada.
  def avisar_contato_em_uso
    return false unless attribute_display_type_in_database == 'contato' && attribute_model_in_database == 'card_attribute'

    automacoes = ::Autonomia::Automacao::EmOutroRegistro.automacoes_que_leem(account, "card.atributos.#{attribute_key_in_database}")
    return false if automacoes.empty?

    errors.add(:base, I18n.t('errors.custom_attribute_definition.contato_em_uso', automacoes: automacoes.map(&:nome).join(', ')))
    true
  end
end

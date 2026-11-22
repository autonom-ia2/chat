# #3082 — apagar um campo de pessoa ou de empresa é "guardar escondido" (decisão do Rodrigo, 21/11/2026).
#
# A definição sai de verdade: as telas, as IAs e a automação, que leem as definições, deixam de ver o campo. O que foi
# escrito nele continua nas pessoas e empresas (`custom_attributes`), como já acontecia. Aqui a conta anota o que é
# preciso para trazer o campo de volta: a chave, o nome, o tipo, o "Para que serve" e as opções da lista.
#
# - Apagar por qualquer caminho anota: o configurador da ficha, a tela antiga de Atributos, o Guia.
# - Criar de novo um campo com a mesma chave (o configurador tira a chave do nome) tira a anotação, e os valores
#   voltam a aparecer, porque nunca saíram.
# - A ficha usa a lista para não mostrar o valor guardado como "campo solto".
class Relationships::CamposGuardados
  CHAVE = 'campos_guardados'.freeze
  MODELOS = %w[contact_attribute company_attribute].freeze
  # Só os mais recentes: a anotação é para trazer de volta, não um histórico. Os valores ficam mesmo assim.
  LIMITE = 100
  CAMPOS = %w[attribute_key attribute_model attribute_display_name attribute_display_type attribute_description attribute_values].freeze

  def initialize(account)
    @account = account
  end

  def lista
    Array(@account.settings&.fetch(CHAVE, nil))
  end

  def guardar!(definition)
    return unless anota?(definition)

    mudar! { |itens| [registro(definition), *sem(itens, definition)].first(LIMITE) }
  end

  # Quase toda criação é de campo que nunca foi apagado: sem anotação dele, nem trava a conta.
  def esquecer!(definition)
    return unless anota?(definition) && sem(lista, definition) != lista

    mudar! { |itens| sem(itens, definition) }
  end

  private

  # A conta apagada leva as definições num job (`dependent: :destroy_async`): sem conta, não há o que anotar.
  def anota?(definition)
    @account.present? && !@account.destroyed? && MODELOS.include?(definition.attribute_model)
  end

  def mudar!
    @account.with_lock do
      atual = lista
      novo = yield(atual)
      @account.update!(settings: (@account.settings || {}).merge(CHAVE => novo)) unless novo == atual
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def registro(definition)
    definition.attributes.slice(*CAMPOS).merge('apagado_em' => Time.current.iso8601)
  end

  def sem(itens, definition)
    itens.reject { |item| item['attribute_model'] == definition.attribute_model && item['attribute_key'] == definition.attribute_key }
  end
end

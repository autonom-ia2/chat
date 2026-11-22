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
  CAMPOS = %w[attribute_key attribute_model attribute_display_name attribute_display_type attribute_description attribute_values].freeze

  def initialize(account)
    @account = account
  end

  def lista
    Array(@account.settings&.fetch(CHAVE, nil))
  end

  def guardar!(definition)
    return unless anota?(definition)

    mudar! { |itens| [registro(definition), *sem(itens, definition)] }
  end

  # A conferência é feita depois de travar e reler a conta: com a conta lida antes, um apagar da mesma chave feito no
  # meio passaria despercebido e o campo trazido de volta ficaria em "Campos apagados".
  def esquecer!(definition)
    return unless anota?(definition)

    mudar! { |itens| sem(itens, definition) }
  end

  private

  # A conta apagada leva as definições num job (`dependent: :destroy_async`): sem conta, não há o que anotar.
  def anota?(definition)
    @account.present? && !@account.destroyed? && MODELOS.include?(definition.attribute_model)
  end

  # A anotação roda depois do commit do apagar, numa transação própria: travar a conta dentro dele inverteria a ordem
  # das travas de Relationships::Configuration#update! (conta, depois definição). Se ela falhar, o campo já saiu e o
  # valor aparece na ficha como campo solto, sem perder nada; criar o campo de novo com o mesmo nome o traz de volta.
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

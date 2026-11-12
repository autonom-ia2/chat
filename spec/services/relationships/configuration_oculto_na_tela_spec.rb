require 'rails_helper'

# #2435: o editor de campos de Relacionamentos também liga e desliga "Mostrar na tela". Cada exemplo diz a falha que pega.
RSpec.describe Relationships::Configuration do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }
  let!(:definition) { create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute') }

  def editar(campos)
    service.update!({ 'revision' => 0, 'definition' => { 'id' => definition.id, 'revision' => definition.updated_at.iso8601(6),
                                                         'attribute_display_name' => 'Contador' }.merge(campos) })
  end

  # MOTIVO: sem a chave no editor, a conta com Relacionamentos ligado não teria como esconder o atributo.
  it 'grava o atributo como fora da tela, e a leitura das definições traz o estado' do
    editar('oculto_na_tela' => true)

    expect(definition.reload.oculto_na_tela).to be(true)
    expect(service.serialize_definition(definition)).to include('oculto_na_tela' => true)
  end

  # MOTIVO: o valor é verdadeiro ou falso; texto ("sim") não passa calado como verdadeiro.
  it 'recusa valor que não é verdadeiro nem falso' do
    expect { editar('oculto_na_tela' => 'sim') }.to raise_error(Relationships::Configuration::Invalid)
    expect(definition.reload.oculto_na_tela).to be(false)
  end
end

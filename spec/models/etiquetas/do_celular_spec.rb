require 'rails_helper'

# #1823, F1b — correspondência entre a etiqueta do celular de uma caixa e a etiqueta daqui.
RSpec.describe Etiquetas::DoCelular do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:label) { create(:label, account: account, title: 'vip') }

  def correspondencia(**atributos)
    described_class.new({ account: account, inbox: inbox, label: label, label_wa_id: '5', nome: 'VIP' }.merge(atributos))
  end

  it 'recusa caixa ou etiqueta de outra conta' do
    outra = create(:account)

    expect(correspondencia(inbox: create(:inbox, account: outra))).not_to be_valid
    expect(correspondencia(label: create(:label, account: outra, title: 'de_fora'))).not_to be_valid
  end

  it 'exige o id da etiqueta no celular e o nome' do
    expect(correspondencia(label_wa_id: '')).not_to be_valid
    expect(correspondencia(nome: '')).not_to be_valid
  end

  it 'uma por etiqueta do celular em cada caixa (índice único)' do
    correspondencia.save!

    expect { correspondencia(nome: 'Outro').save! }.to raise_error(ActiveRecord::RecordNotUnique)
    expect(correspondencia(inbox: create(:inbox, account: account))).to be_valid
  end

  it 'some quando a etiqueta ou a caixa são apagadas; a etiqueta fica quando a correspondência some' do
    correspondencia.save!
    label.destroy!
    expect(described_class.count).to eq(0)

    nova = create(:label, account: account, title: 'novo')
    correspondencia(label: nova).save!
    inbox.destroy!
    expect(described_class.count).to eq(0)
    expect(Label.exists?(nova.id)).to be(true)
  end
end

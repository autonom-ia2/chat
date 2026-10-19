require 'rails_helper'

# #1823, F1a — o nome livre é da etiqueta da própria conta, um por etiqueta, e cai junto com ela.
RSpec.describe Etiquetas::Nome do
  let(:account) { create(:account) }
  let(:label) { create(:label, account: account, title: 'vip') }

  it 'recusa etiqueta de outra conta' do
    de_fora = create(:label, account: create(:account), title: 'de_fora')

    expect(described_class.new(account: account, label: de_fora, nome: 'Cliente VIP')).not_to be_valid
  end

  it 'aceita um nome por etiqueta, até 80 caracteres' do
    described_class.create!(account: account, label: label, nome: 'Cliente VIP')

    expect(described_class.new(account: account, label: label, nome: 'Outro')).not_to be_valid
    expect(described_class.new(account: account, label: create(:label, account: account), nome: 'a' * 81)).not_to be_valid
  end

  it 'some quando a etiqueta é apagada' do
    described_class.create!(account: account, label: label, nome: 'Cliente VIP')

    label.destroy!

    expect(described_class.count).to eq(0)
  end
end

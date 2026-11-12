require 'rails_helper'

# #2435: a IA recebe o critério escrito na etiqueta. Cada exemplo diz a falha que pega.
RSpec.describe Autonomia::DescricoesDasEtiquetas do
  let(:account) { create(:account) }

  # MOTIVO: a etiqueta sem descrição continua igual (só o nome); descrição em branco não vira critério vazio.
  it 'devolve só as etiquetas pedidas que têm descrição, sem espaço nas pontas' do
    create(:label, account: account, title: 'vip', description: '  cliente com mais de 3 apólices ')
    create(:label, account: account, title: 'frota', description: nil)
    create(:label, account: account, title: 'renovacao', description: '   ')
    create(:label, account: account, title: 'sinistro', description: 'tem sinistro aberto')

    expect(described_class.de(account, %w[vip frota renovacao])).to eq('vip' => 'cliente com mais de 3 apólices')
  end

  # MOTIVO: o G29 (#2702) grava na descrição o texto do dado que virou a etiqueta (pode ser de terceiro). Ele não é
  # critério e não pode chegar à IA como se a equipe tivesse escrito.
  it 'deixa de fora a descrição que só repete o nome, como a que a automação grava' do
    create(:label, account: account, title: 'black_friday_50_off', description: 'Black Friday, 50% off')
    create(:label, account: account, title: 'vip', description: 'VIP')
    create(:label, account: account, title: 'sinistro', description: 'tem sinistro aberto')

    expect(described_class.de(account, %w[black_friday_50_off vip sinistro])).to eq('sinistro' => 'tem sinistro aberto')
  end

  # MOTIVO: a mesma conversa tem de gerar o mesmo texto para a IA, na ordem das etiquetas da conversa.
  it 'segue a ordem dos nomes pedidos' do
    create(:label, account: account, title: 'vip', description: 'cliente com mais de 3 apólices')
    create(:label, account: account, title: 'sinistro', description: 'tem sinistro aberto')

    expect(described_class.de(account, %w[sinistro vip]).keys).to eq(%w[sinistro vip])
  end

  # MOTIVO: a etiqueta de outra conta, com o mesmo nome, não pode emprestar a descrição.
  it 'lê só as etiquetas da própria conta' do
    create(:label, account: create(:account), title: 'vip', description: 'de outra conta')

    expect(described_class.de(account, %w[vip])).to eq({})
  end

  # MOTIVO: conversa sem etiqueta não consulta nada nem quebra.
  it 'sem nomes, devolve vazio' do
    expect(described_class.de(account, [])).to eq({})
  end
end

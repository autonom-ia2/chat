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

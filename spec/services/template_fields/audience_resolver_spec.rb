require 'rails_helper'

RSpec.describe TemplateFields::AudienceResolver do
  let(:resolver) do
    described_class.new(columns: %w[Vencimento Valor Plano],
                        values: { 'Vencimento' => '2026-10-14', 'Valor' => '1234.5', 'Plano' => 'Ouro' },
                        types: { 'Vencimento' => 'data', 'Valor' => 'moeda' })
  end

  it 'offers every column of the audience as publico.<header>' do
    expect(resolver.keys).to eq(['publico.Vencimento', 'publico.Valor', 'publico.Plano'])
  end

  it 'formats each cell by the type of its column' do
    expect(resolver.value('publico.Vencimento')).to eq('14/10/2026')
    expect(resolver.value('publico.Valor')).to eq('R$ 1.234,50')
    expect(resolver.value('publico.Plano')).to eq('Ouro')
  end

  it 'answers nothing for an unknown column or a blank cell' do
    expect(resolver.value('publico.Outra')).to be_nil
    expect(described_class.new(columns: ['Plano'], values: {}).value('publico.Plano')).to be_nil
    expect(resolver.value('cliente.nome')).to be_nil
  end
end

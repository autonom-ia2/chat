require 'rails_helper'

# O pedido da `relatorio_de_atendimento` (#3158): quando a série troca de agrupamento.
RSpec.describe Autonomia::Guide::Relatorio::Pedido do
  let(:account) { create(:account) }

  def pedido(primeiro, ultimo, agrupar: 'dia')
    described_class.new(account: account, params: { 'tipo' => 'serie', 'metrica' => 'resolutions_count',
                                                    'de' => primeiro, 'ate' => ultimo, 'agrupar' => agrupar })
  end

  describe 'agrupamento da série' do
    it 'até 31 dias fica por dia' do
      expect(pedido('2026-01-01', '2026-01-31').agrupar).to eq('dia')
    end

    it 'acima de 31 dias passa para semana', :aggregate_failures do
      resultado = pedido('2026-01-01', '2026-02-01')

      expect(resultado.agrupar).to eq('semana')
      expect(resultado).to be_reagrupado
    end

    # 217 dias são 31 semanas cheias, mas começando numa quinta tocam 32 semanas de segunda a domingo.
    it 'conta as semanas como o banco agrupa, a partir de segunda', :aggregate_failures do
      expect(Date.new(2026, 1, 1)).to be_thursday
      expect(pedido('2026-01-01', '2026-08-05').agrupar).to eq('mes')
      expect(pedido('2026-01-05', '2026-08-09').agrupar).to eq('semana')
    end

    it 'pedido por semana com mais de 31 semanas passa para mês' do
      expect(pedido('2026-01-01', '2026-08-05', agrupar: 'semana').agrupar).to eq('mes')
    end
  end
end

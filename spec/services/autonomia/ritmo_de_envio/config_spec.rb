require 'rails_helper'

RSpec.describe Autonomia::RitmoDeEnvio::Config do
  describe '.normalizar' do
    it 'guarda o limite e o horário escolhidos, com os dias em ordem e sem repetir' do
      valores = { limite: { mensagens: '3', dias: 7 }, horario: { inicio: 8, fim: '20', dias_da_semana: [5, 1, '1', 3] } }

      expect(described_class.normalizar(valores)).to eq(
        'limite' => { 'mensagens' => 3, 'dias' => 7 },
        'intervalo' => nil,
        'horario' => { 'inicio' => 8, 'fim' => 20, 'dias_da_semana' => [1, 3, 5] }
      )
    end

    it 'guarda nil para sem limite, sem intervalo e a qualquer hora' do
      expect(described_class.normalizar(limite: nil, intervalo: nil, horario: nil))
        .to eq('limite' => nil, 'intervalo' => nil, 'horario' => nil)
    end

    it 'guarda o intervalo mínimo em horas (#3101)' do
      expect(described_class.normalizar(intervalo: { horas: '4' })['intervalo']).to eq('horas' => 4)
    end

    it 'recusa o que a tela não oferece, dizendo o campo' do
      erros = [
        [{ limite: { mensagens: 0, dias: 7 } }, 'limite.mensagens'],
        [{ limite: { mensagens: 2, dias: 3 } }, 'limite.dias'],
        [{ intervalo: { horas: 3 } }, 'intervalo.horas'],
        [{ intervalo: { horas: 'x' } }, 'intervalo.horas'],
        [{ horario: { inicio: 20, fim: 8, dias_da_semana: [1] } }, 'horario.fim'],
        [{ horario: { inicio: 8, fim: 20, dias_da_semana: [] } }, 'horario.dias_da_semana'],
        [{ horario: { inicio: 8, fim: 20, dias_da_semana: [7] } }, 'horario.dias_da_semana']
      ]

      erros.each do |valores, campo|
        expect { described_class.normalizar(valores) }.to raise_error(described_class::Invalida, campo)
      end
    end
  end
end

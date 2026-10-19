require 'rails_helper'

RSpec.describe Crm::Numeros::Mes do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }

  def mes(chave = nil)
    described_class.new(account: account, chave: chave)
  end

  it 'conta o mês no fuso da conta: 31/10 às 22h em São Paulo ainda é outubro' do
    travel_to Time.utc(2026, 11, 1, 1, 0) do
      expect(mes.info).to include(chave: '2026-10', dia: 31, diasNoMes: 31, diasRestantes: 0, fechado: false,
                                  anterior: '2026-09', seguinte: nil)
      expect(mes.range.begin).to eq(Time.find_zone('America/Sao_Paulo').local(2026, 10, 1))
    end
  end

  it 'mês fechado: o dia é o último, sem dias restantes, e as setas andam nos dois sentidos' do
    travel_to Time.utc(2026, 10, 19, 15, 0) do
      info = mes('2026-09').info

      expect(info).to include(chave: '2026-09', dia: 30, diasNoMes: 30, diasRestantes: 0, fechado: true,
                              anterior: '2026-08', seguinte: '2026-10')
      expect(mes('2026-09').range.end).to eq(Time.find_zone('America/Sao_Paulo').local(2026, 9, 30).end_of_day)
    end
  end

  it 'para a seta de voltar no limite de meses atrás' do
    travel_to Time.utc(2026, 10, 19, 15, 0) do
      expect(mes('2025-10').info[:anterior]).to be_nil
    end
  end

  it 'recusa mês futuro, mês além do limite e texto que não é mês' do
    travel_to Time.utc(2026, 10, 19, 15, 0) do
      %w[2026-11 2025-09 2026-13 2026-1 outubro 2026-10-01].each do |chave|
        expect { mes(chave) }.to raise_error(described_class::Invalido), chave
      end
    end
  end
end

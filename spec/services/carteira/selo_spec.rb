require 'rails_helper'

# E4 (#2897): o selo do seguro e o dia de hoje da conta. O selo não é coluna: sai da data, no fuso da conta.
RSpec.describe Carteira::Selo do
  let(:hoje) { Date.new(2026, 11, 12) }

  def seguro(termina:, cancelado: false)
    Carteira::Apolice.new(fim_vigencia: termina, cancelado_em: (Time.current if cancelado))
  end

  it 'dá o selo e os dias de cada situação: no dia do vencimento ainda vale, no dia seguinte venceu' do
    tabela = {
      'vence daqui a 34 dias' => [seguro(termina: hoje + 34), 'ativo', 34],
      'vence hoje' => [seguro(termina: hoje), 'ativo', 0],
      'venceu ontem' => [seguro(termina: hoje - 1), 'vencido', -1],
      'cancelado que ainda valeria' => [seguro(termina: hoje + 34, cancelado: true), 'cancelado', 34],
      'cancelado que já venceu' => [seguro(termina: hoje - 1, cancelado: true), 'cancelado', -1]
    }

    tabela.each do |caso, (apolice, selo, dias)|
      expect([described_class.de(apolice, hoje: hoje), described_class.dias(apolice, hoje: hoje)]).to eq([selo, dias]), caso
    end
  end

  it 'põe na frente o que pede atenção, o cancelado por último e, no empate, quem termina antes' do
    apolices = [seguro(termina: hoje + 90), seguro(termina: hoje + 5, cancelado: true), seguro(termina: hoje - 3), seguro(termina: hoje + 10)]
    apolices.each_with_index { |apolice, indice| apolice.id = indice + 1 }

    expect(described_class.por_urgencia(apolices, hoje: hoje).map(&:id)).to eq([3, 4, 1, 2])
  end

  describe 'o dia de hoje' do
    # São Paulo fica três horas atrás do servidor (UTC).
    let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
    let(:vence_dia_12) { seguro(termina: hoje) }

    it 'às 22h da conta ainda é o dia 12, mesmo com o servidor já no dia 13: o seguro que vence hoje não aparece vencido' do
      travel_to(Time.utc(2026, 11, 13, 1)) do
        hoje_da_conta = described_class.hoje(account)

        expect([Time.current.utc.to_date, hoje_da_conta]).to eq([Date.new(2026, 11, 13), hoje])
        expect(described_class.de(vence_dia_12, hoje: hoje_da_conta)).to eq('ativo')
      end
    end

    it 'à 1h da conta já é o dia 13: o seguro que vencia no dia 12 venceu' do
      travel_to(Time.utc(2026, 11, 13, 4)) do
        hoje_da_conta = described_class.hoje(account)

        expect(hoje_da_conta).to eq(Date.new(2026, 11, 13))
        expect(described_class.de(vence_dia_12, hoje: hoje_da_conta)).to eq('vencido')
        expect(described_class.dias(vence_dia_12, hoje: hoje_da_conta)).to eq(-1)
      end
    end

    it 'segue o fuso de cada conta, não um fuso fixo: na mesma hora, Tóquio já virou o dia e São Paulo não' do
      toquio = create(:account, reporting_timezone: 'Asia/Tokyo')

      travel_to(Time.utc(2026, 11, 12, 16)) do
        expect([described_class.hoje(account), described_class.hoje(toquio)]).to eq([hoje, Date.new(2026, 11, 13)])
      end
    end
  end
end

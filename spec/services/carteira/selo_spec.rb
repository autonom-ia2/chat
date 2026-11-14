require 'rails_helper'

# E4 (#2897): o selo do seguro e o dia de hoje da conta. O selo não é coluna: sai da data, no fuso da conta. Com a
# renovação (E5, #2898) entram Renovado e Em renovação, pelas colunas que o desfecho do card mantém.
RSpec.describe Carteira::Selo do
  let(:hoje) { Date.new(2026, 11, 12) }

  def seguro(termina:, cancelado: false, **renovacao)
    Carteira::Apolice.new(fim_vigencia: termina, cancelado_em: (Time.current if cancelado), **renovacao)
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

  it 'com a renovação: o card aberto dá Em renovação, o renovado é Renovado mesmo depois do fim, e o cancelado ganha de todos' do
    agora = Time.current
    tabela = {
      'com card de renovação, ainda valendo' => [seguro(termina: hoje + 20, crm_card_id: 7), 'em_renovacao'],
      'com card, no dia do vencimento' => [seguro(termina: hoje, crm_card_id: 7), 'em_renovacao'],
      'com card, já vencido' => [seguro(termina: hoje - 1, crm_card_id: 7), 'vencido'],
      'renovado, ainda valendo' => [seguro(termina: hoje + 20, crm_card_id: 7, renovado_em: agora), 'renovado'],
      'renovado, depois do fim' => [seguro(termina: hoje - 40, crm_card_id: 7, renovado_em: agora), 'renovado'],
      'renovado sem card' => [seguro(termina: hoje + 20, renovado_em: agora), 'renovado'],
      'não renovou, ainda valendo' => [seguro(termina: hoje + 20, crm_card_id: 7, nao_renovou_em: agora), 'ativo'],
      'não renovou, depois do fim' => [seguro(termina: hoje - 1, crm_card_id: 7, nao_renovou_em: agora), 'vencido'],
      'card tirado do quadro' => [seguro(termina: hoje + 20, crm_card_id: 7, renovacao_card_removido_em: agora), 'ativo'],
      'renovado e cancelado' => [seguro(termina: hoje + 20, cancelado: true, crm_card_id: 7, renovado_em: agora), 'cancelado']
    }

    tabela.each { |caso, (apolice, selo)| expect(described_class.de(apolice, hoje: hoje)).to eq(selo), caso }
  end

  it 'põe na frente o que pede atenção, o cancelado por último e, no empate, quem termina antes' do
    apolices = [seguro(termina: hoje + 90), seguro(termina: hoje + 5, cancelado: true), seguro(termina: hoje - 3), seguro(termina: hoje + 10),
                seguro(termina: hoje + 50, renovado_em: Time.current), seguro(termina: hoje + 60, crm_card_id: 7)]
    apolices.each_with_index { |apolice, indice| apolice.id = indice + 1 }

    expect(described_class.por_urgencia(apolices, hoje: hoje).map(&:id)).to eq([3, 6, 5, 4, 1, 2])
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

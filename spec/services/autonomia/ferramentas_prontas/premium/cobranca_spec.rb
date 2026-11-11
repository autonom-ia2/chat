require 'rails_helper'

# #2858 (F7): a grátis que volta ao saldo quando a entrega fica incerta (`Cobranca.desfazer_cobranca!`). Com o mês
# acima das 20 grátis, só baixar o contador roubava uma grátis do cliente: a próxima consulta continuava cobrada e o mês
# fechava com 19 grátis. A cobrada mais antiga do mês vira a grátis que faltou.
RSpec.describe Autonomia::FerramentasProntas::Premium::Cobranca do
  let(:account) { create(:account) }
  let(:premium) { Autonomia::FerramentasProntas::Premium }
  let(:mes) { Date.new(2026, 11, 1) }

  def registro!(numero)
    cobrada = numero > premium::GRATIS
    premium::Registro.create!(account: account, fonte: 'certidoes_empresa', consulta: 'divida_uniao', dataset: 'ondemand_pgfn_company',
                              dia: mes + 2.days, resultado: 'encontrado', numero: numero, cobranca: cobrada ? 'cobrada' : 'gratis',
                              custo: BigDecimal('0.10'), preco: cobrada ? BigDecimal('0.15') : 0)
  end

  def mes_com(contadas)
    premium::Saldo.create!(account: account, fonte: 'certidoes_empresa', mes: mes, contadas: contadas)
    (1..contadas).map { |numero| registro!(numero) }
  end

  it 'saldo 25: a grátis desfeita volta convertendo a cobrada mais antiga do mês, e o mês fecha com 20 grátis' do
    registros = mes_com(25)

    described_class.desfazer_cobranca!(registros[4])

    expect(registros[4].reload).to have_attributes(cobranca: 'sem_cobranca', preco: 0, numero: nil, motivo: 'entrega_incerta')
    expect(registros[20].reload).to have_attributes(cobranca: 'gratis', preco: 0, custo: BigDecimal('0.10'))
    expect(premium::Registro.where(cobranca: 'gratis').count).to eq(20)
    expect(premium::Registro.where(cobranca: 'cobrada').order(:numero).pluck(:numero)).to eq([22, 23, 24, 25])
    expect(premium::Saldo.sole.contadas).to eq(24)
  end

  it 'saldo 25: a próxima consulta do mês segue cobrada, e as grátis não passam de 20' do
    registros = mes_com(25)
    described_class.desfazer_cobranca!(registros[0])

    proxima = premium::Saldo.contar!(account_id: account.id, fonte: 'certidoes_empresa', mes: mes)

    expect(proxima).to be > premium::GRATIS
  end

  it 'saldo 10: só baixa o contador, e a próxima consulta usa a grátis que voltou' do
    registros = mes_com(10)

    described_class.desfazer_cobranca!(registros[9])

    expect(premium::Saldo.sole.contadas).to eq(9)
    expect(premium::Registro.where(cobranca: 'gratis').count).to eq(9)
    expect(premium::Saldo.contar!(account_id: account.id, fonte: 'certidoes_empresa', mes: mes)).to eq(10)
  end

  it 'a cobrada desfeita só perde o preço: o saldo e as grátis não mudam' do
    registros = mes_com(25)

    described_class.desfazer_cobranca!(registros[24])

    expect(registros[24].reload).to have_attributes(cobranca: 'sem_cobranca', preco: 0)
    expect(premium::Registro.where(cobranca: 'gratis').count).to eq(20)
    expect(premium::Saldo.sole.contadas).to eq(25)
  end

  it 'a cobrada de outro card ou de outro mês nunca vira a grátis devolvida' do
    registros = mes_com(21)
    registros[20].update!(fonte: 'raio_x_empresa')

    described_class.desfazer_cobranca!(registros[0])

    expect(registros[20].reload.cobranca).to eq('cobrada')
    expect(premium::Saldo.sole.contadas).to eq(20)
  end
end

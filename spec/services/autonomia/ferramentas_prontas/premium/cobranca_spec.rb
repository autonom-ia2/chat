require 'rails_helper'

# #2858 (F7): a grátis que volta ao saldo quando a entrega fica incerta (`Cobranca.desfazer_cobranca!`). Com o mês
# acima das 20 grátis, só baixar o contador roubava uma grátis do cliente: a próxima consulta continuava cobrada e o mês
# fechava com 19 grátis. A cobrada mais antiga do mês vira a grátis que faltou.
RSpec.describe Autonomia::FerramentasProntas::Premium::Cobranca do
  let(:account) { create(:account) }
  let(:premium) { Autonomia::FerramentasProntas::Premium }
  # O mês corrente da conta: a entrega incerta de um mês anterior tem regra própria.
  let(:mes) { premium.mes_da_conta(account) }

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

  # Revisor (cobranca.rb:62): a cobrada desfeita também não contou. Sem baixar o contador, desfazer uma cobrada e depois
  # uma grátis deixava o saldo um acima do real, e o cliente pagava uma consulta que devia ser grátis.
  it 'a cobrada desfeita perde o preço e baixa o contador (não contou); as grátis não mudam' do
    registros = mes_com(25)

    described_class.desfazer_cobranca!(registros[24])

    expect(registros[24].reload).to have_attributes(cobranca: 'sem_cobranca', preco: 0)
    expect(premium::Registro.where(cobranca: 'gratis').count).to eq(20)
    expect(premium::Saldo.sole.contadas).to eq(24)
  end

  it 'saldo 21: desfaz a cobrada e depois uma grátis; a próxima consulta é grátis, e o mês fecha com 20 grátis' do
    registros = mes_com(21)

    described_class.desfazer_cobranca!(registros[20])
    described_class.desfazer_cobranca!(registros[0])

    expect(premium::Saldo.sole.contadas).to eq(19)
    expect(premium::Saldo.contar!(account_id: account.id, fonte: 'certidoes_empresa', mes: mes)).to eq(20)
  end

  # Revisor (cobranca.rb:45): o `registrar!` trava o Saldo (contar!) e depois grava o Registro; o `entrega_incerta!`
  # travava o Registro e depois o Saldo (`devolver!`). A ordem invertida podia virar deadlock: o Saldo vem antes.
  it 'a entrega incerta trava o Saldo antes do Registro, na mesma ordem da cobrança' do
    registros = mes_com(3)
    agente = Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom')
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, premium::FLAG)
    ferramenta = incluir_pronta('certidoes_empresa', conta: account, agente: agente)
    registros[2].update!(tool_run_id: 4242)
    run = instance_double(Autonomia::Agents::ToolRun, id: 4242, ferramenta: ferramenta, account: account,
                                                      arguments: { 'consulta' => 'divida_uniao' })
    ordem = []
    { saldo: premium::Saldo, registro: premium::Registro }.each do |nome, modelo|
      allow(modelo).to receive(:lock).and_wrap_original do |original, *args|
        ordem << nome
        original.call(*args)
      end
    end

    described_class.entrega_incerta!(run)

    expect(ordem.first).to eq(:saldo)
    expect(registros[2].reload.cobranca).to eq('sem_cobranca')
    expect(premium::Saldo.sole.contadas).to eq(2)
  end

  # Revisor (cobranca.rb:73): o mês anterior já fechou (a fatura sai da telemetria). A entrega incerta que chega depois
  # não converte cobrada nem mexe no saldo daquele mês: a linha dela fica sem cobrança, e o caso vai ao log.
  it 'entrega incerta de um mês anterior: não converte cobrada nem mexe no saldo; só registra no log' do
    registros = mes_com(25)
    allow(Rails.logger).to receive(:warn)

    travel_to(mes.next_month.in_time_zone + 4.days) { described_class.desfazer_cobranca!(registros[4]) }

    expect(registros[4].reload.cobranca).to eq('sem_cobranca')
    expect(registros[20].reload.cobranca).to eq('cobrada')
    expect(premium::Saldo.sole.contadas).to eq(25)
    expect(Rails.logger).to have_received(:warn).with(include('mês anterior'))
  end

  it 'a cobrada de outro card ou de outro mês nunca vira a grátis devolvida' do
    registros = mes_com(21)
    registros[20].update!(fonte: 'raio_x_empresa')

    described_class.desfazer_cobranca!(registros[0])

    expect(registros[20].reload.cobranca).to eq('cobrada')
    expect(premium::Saldo.sole.contadas).to eq(20)
  end

  # Revisor (lote 3, cobranca.rb:78): o `FOR UPDATE` da cobrada mais antiga pode voltar vazio quando outra transação a
  # muda enquanto ele espera a trava (o Postgres reavalia a linha e não busca a seguinte). Com o mês acima das 20, vazio
  # quer dizer corrida: a busca se repete, num retrato novo do banco.
  it 'saldo 25 e a busca da cobrada mais antiga volta vazia uma vez (corrida): repete e converte a seguinte' do
    registros = mes_com(25)
    chamadas = 0
    allow(described_class).to receive(:cobrada_mais_antiga).and_wrap_original do |original, *argumentos|
      chamadas += 1
      chamadas == 1 ? nil : original.call(*argumentos)
    end

    described_class.desfazer_cobranca!(registros[4])

    expect(chamadas).to eq(2)
    expect(premium::Registro.where(cobranca: 'gratis').count).to eq(20)
    expect(premium::Saldo.sole.contadas).to eq(24)
  end

  it 'sem cobrada nenhuma depois das tentativas: o contador baixa e o caso vai ao log' do
    registros = mes_com(25)
    allow(described_class).to receive(:cobrada_mais_antiga).and_return(nil)
    allow(Rails.logger).to receive(:warn)

    described_class.desfazer_cobranca!(registros[4])

    expect(described_class).to have_received(:cobrada_mais_antiga).exactly(described_class::TENTATIVAS_DA_CONVERSAO).times
    expect(Rails.logger).to have_received(:warn).with(include('cobrada para converter'))
    expect(premium::Saldo.sole.contadas).to eq(24)
  end
end

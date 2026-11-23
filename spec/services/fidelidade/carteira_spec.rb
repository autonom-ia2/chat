require 'rails_helper'

# #3100 — o cartão de uma pessoa: movimento e saldo juntos, as saídas pelas entradas mais antigas, o prêmio só com o
# cartão completo, o ajuste e o vencimento.
RSpec.describe Fidelidade::Carteira do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:agora) { Time.zone.parse('2026-11-23 12:00:00') }
  let(:programa) do
    Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                 premio: 'Uma lavagem grátis', validade_meses: 3, ligado: true, ligado_em: agora - 1.year)
  end

  before { travel_to(agora) }

  def carteira = described_class.new(programa, ana)

  def saldo = Fidelidade::Saldo.find_by(programa_id: programa.id, contact_id: ana.id).saldo

  def presente(quantos, em: agora) = carteira.entrar(tipo: 'presente', quantos: quantos, agora: em)

  it 'a entrada soma no saldo, guarda o resto e quando vence' do
    entrada = presente(4)

    expect(saldo).to eq(4)
    expect(entrada).to have_attributes(quantos: 4, restante: 4, vence_em: agora + 3.months)
  end

  it 'a saída tira das entradas mais antigas primeiro' do
    antiga = presente(3, em: agora - 2.months)
    nova = presente(5)

    carteira.sair(tipo: 'ajuste', quantos: 4)

    expect([antiga.reload.restante, nova.reload.restante, saldo]).to eq([0, 4, 4])
  end

  it 'o prêmio só sai com o cartão completo, e o que passa da meta fica' do
    presente(9)
    expect { Fidelidade::DarPremio.new(programa, ana, admin).call }.to raise_error(described_class::SaldoInsuficiente)

    presente(3)
    premio = Fidelidade::DarPremio.new(programa, ana, admin).call

    expect(premio).to have_attributes(tipo: 'premio', quantos: -10, user: admin)
    expect(saldo).to eq(2)
  end

  it 'diz quando o saldo cruzou a meta' do
    cheia = carteira
    cheia.entrar(tipo: 'presente', quantos: 8)
    expect(cheia.completou?).to be(false)

    cheia.entrar(tipo: 'presente', quantos: 3)
    expect(cheia.completou?).to be(true)
  end

  it 'o ajuste para menos recusa tirar mais do que a pessoa tem' do
    presente(2)

    expect { Fidelidade::Ajustar.new(programa, ana, admin).call(-3, 'erro de digitação') }
      .to raise_error(described_class::SaldoInsuficiente)
    expect(saldo).to eq(2)

    movimento = Fidelidade::Ajustar.new(programa, ana, admin).call(-2, 'erro de digitação')
    expect(movimento).to have_attributes(tipo: 'ajuste', quantos: -2, motivo: 'erro de digitação', user: admin)
    expect(saldo).to eq(0)
  end

  it 'vence o que sobrou das entradas vencidas, num movimento só' do
    velha = presente(3, em: agora - 4.months)
    presente(2, em: agora - 4.months + 1.day)
    nova = presente(5)
    carteira.sair(tipo: 'ajuste', quantos: 1)

    venceu = carteira.vencer(agora)

    expect(venceu).to have_attributes(tipo: 'venceu', quantos: -4)
    expect(velha.reload.restante).to eq(0)
    expect(nova.reload.restante).to eq(5)
    expect(saldo).to eq(5)
    expect(carteira.vencer(agora)).to be_nil
  end
end

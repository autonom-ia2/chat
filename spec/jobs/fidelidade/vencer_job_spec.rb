require 'rails_helper'

# #3100 — a rotina diária vence os carimbos que passaram da validade, em todas as contas, uma vez só.
RSpec.describe Fidelidade::VencerJob do
  let(:account) { create(:account) }
  let(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:agora) { Time.zone.parse('2026-11-23 12:30:00') }
  let(:programa) do
    Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                 premio: 'Uma lavagem grátis', validade_meses: 3, ligado: true, ligado_em: agora - 1.year)
  end

  before do
    travel_to(agora)
    carteira = Fidelidade::Carteira.new(programa, ana)
    carteira.entrar(tipo: 'presente', quantos: 3, agora: agora - 4.months)
    carteira.entrar(tipo: 'presente', quantos: 2, agora: agora - 1.month)
  end

  it 'vence o que passou da validade e deixa o resto' do
    described_class.perform_now
    described_class.perform_now

    expect(Fidelidade::Saldo.find_by(contact_id: ana.id).saldo).to eq(2)
    expect(Fidelidade::Movimento.where(contact_id: ana.id, tipo: 'venceu').pluck(:quantos)).to eq([-3])
  end
end

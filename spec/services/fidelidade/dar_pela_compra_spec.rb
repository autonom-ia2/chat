require 'rails_helper'

# #3100 — a compra (o card ganho) vira carimbo do cartão fidelidade. As decisões do Rodrigo (23/11): compra de antes de
# ligar o cartão não conta (D2) e o troco não passa para a próxima (D3). O card desfeito estorna, sem deixar o saldo
# negativo, e o mesmo card nunca dá carimbo duas vezes.
RSpec.describe Fidelidade::DarPelaCompra do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:agora) { Time.zone.parse('2026-11-23 12:00:00') }
  let(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:bruno) { create(:contact, account: account, name: 'Bruno Brandolim') }
  let!(:programa) do
    Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                 premio: 'Uma lavagem grátis', ligado: true, ligado_em: agora - 30.days)
  end
  let(:gatilho) { Fidelidade::CartaoCompleto::GATILHO }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { travel_to(agora) }

  def compra(pessoa, reais:, dias: 1, moeda: 'BRL')
    card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: pessoa, title: 'Pedido',
                                     value_cents: reais * 100, currency: moeda, status: :won)
    card.tap { |ganho| ganho.update!(closed_at: agora - dias.days) }
  end

  def dar(*pessoas) = described_class.new(account, contact_ids: pessoas.map(&:id)).call

  def saldo(pessoa) = Fidelidade::Saldo.find_by(programa_id: programa.id, contact_id: pessoa.id)&.saldo || 0

  def movimentos(pessoa) = Fidelidade::Movimento.where(contact_id: pessoa.id).order(:id)

  it 'dá os carimbos pelo valor, sem troco: R$ 120 a cada R$ 50 dá 2' do
    card = compra(ana, reais: 120)

    dar(ana)

    expect(saldo(ana)).to eq(2)
    expect(movimentos(ana).sole).to have_attributes(tipo: 'compra', quantos: 2, restante: 2, origem: card, vez: 1,
                                                    valor_centavos: 12_000, moeda: 'BRL')
  end

  it 'rodar de novo não dá carimbo duas vezes' do
    compra(ana, reais: 120)

    2.times { dar(ana) }

    expect(saldo(ana)).to eq(2)
    expect(movimentos(ana).count).to eq(1)
  end

  it 'não conta compra de antes de ligar o cartão, nem com o cartão pausado, nem em outra moeda' do
    compra(ana, reais: 500, dias: 40)
    compra(ana, reais: 500, moeda: 'USD')
    dar(ana)
    programa.update!(ligado: false)
    compra(ana, reais: 500)
    dar(ana)

    expect(saldo(ana)).to eq(0)
    expect(movimentos(ana)).to be_empty
  end

  it 'compra abaixo do "a cada" não dá carimbo nem movimento' do
    compra(ana, reais: 49)

    dar(ana)

    expect(movimentos(ana)).to be_empty
  end

  it 'card reaberto estorna; ganho de novo, dá outra vez' do
    card = compra(ana, reais: 100)
    dar(ana)
    card.update!(status: :open, closed_at: nil)
    dar(ana)

    expect(saldo(ana)).to eq(0)
    expect(movimentos(ana).pluck(:tipo, :quantos, :vez)).to eq([['compra', 2, 1], ['estorno', -2, 1]])

    card.update!(status: :won, closed_at: agora)
    dar(ana)

    expect(saldo(ana)).to eq(2)
    expect(movimentos(ana).last).to have_attributes(tipo: 'compra', quantos: 2, vez: 2)
  end

  it 'o valor mudou depois do ganho: estorna e dá pelo valor novo' do
    card = compra(ana, reais: 100)
    dar(ana)
    card.update!(value_cents: 25_000)
    dar(ana)

    expect(saldo(ana)).to eq(5)
    expect(movimentos(ana).pluck(:tipo, :quantos)).to eq([['compra', 2], ['estorno', -2], ['compra', 5]])
  end

  it 'card levado para outra pessoa: sai de uma e entra na outra' do
    card = compra(ana, reais: 100)
    dar(ana)
    card.update!(contact: bruno)
    dar(ana, bruno)

    expect([saldo(ana), saldo(bruno)]).to eq([0, 2])
  end

  it 'o estorno nunca deixa o saldo negativo: quem já usou os carimbos fica com zero' do
    card = compra(ana, reais: 500)
    dar(ana)
    Fidelidade::DarPremio.new(programa, ana, admin).call
    card.update!(status: :lost)
    dar(ana)

    expect(saldo(ana)).to eq(0)
    expect(movimentos(ana).last).to have_attributes(tipo: 'estorno', quantos: 0)
  end

  it 'sem contact_ids, acerta a conta inteira' do
    compra(ana, reais: 100)
    compra(bruno, reais: 150)

    described_class.new(account).call

    expect([saldo(ana), saldo(bruno)]).to eq([2, 3])
  end

  it 'conta sem cartão: não faz nada' do
    programa.destroy!
    compra(ana, reais: 100)

    expect { dar(ana) }.not_to change(Fidelidade::Movimento, :count)
  end

  it 'os carimbos vencem pela data da compra, quando o cartão tem validade' do
    programa.update!(validade_meses: 6)
    compra(ana, reais: 100, dias: 2)

    dar(ana)

    expect(movimentos(ana).sole.vence_em).to eq(agora - 2.days + 6.months)
  end

  describe 'o gatilho "completou o cartão"' do
    before { allow(Autonomia::Automacao::Escuta).to receive(:comecar) }

    def com_automacao_ligada
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).and_call_original
      ligadas = instance_double(ActiveRecord::Relation, exists?: true)
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).with(account.id, gatilho).and_return(ligadas)
    end

    it 'dispara uma vez quando a compra cruza a meta, com a marca do movimento' do
      com_automacao_ligada
      compra(ana, reais: 400)
      dar(ana)
      compra(ana, reais: 120)

      dar(ana)
      dar(ana)

      movimento = movimentos(ana).last
      expect(Autonomia::Automacao::Escuta).to have_received(:comecar).once
      expect(Autonomia::Automacao::Escuta).to have_received(:comecar)
        .with(ana, gatilho, evento: "#{gatilho}:#{ana.id}:#{movimento.id}")
    end

    it 'não dispara sem automação ligada com o gatilho' do
      compra(ana, reais: 600)

      dar(ana)

      expect(saldo(ana)).to eq(12)
      expect(Autonomia::Automacao::Escuta).not_to have_received(:comecar)
    end
  end
end

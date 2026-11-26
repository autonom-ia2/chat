require 'rails_helper'

RSpec.describe Autonomia::Agents::CotacaoDeViagem do
  let(:account) { create(:account) }
  let(:agente) { Autonomia::Agents::Agent.create!(account: account, name: 'Agente', agent_type: 'custom') }
  let(:conversa) { create(:conversation, account: account) }

  def criar_cotacao(planos: [], pedido: {})
    described_class.create!(account: account, conversation: conversa, agent: agente, id_cotacao: SecureRandom.hex(4),
                            planos: planos, pedido: pedido)
  end

  it 'a última da conversa é a de maior id' do
    criar_cotacao(planos: [{ 'codigo' => 'P1' }])
    b = criar_cotacao(planos: [{ 'codigo' => 'P1' }])
    expect(described_class.ultima_da_conversa(conversa.id, agente.id)).to eq(b)
  end

  it 'a última da conversa é a do agente pedido, nunca a de outro agente na mesma conversa' do
    deste = criar_cotacao(planos: [{ 'codigo' => 'P1' }])
    outro = Autonomia::Agents::Agent.create!(account: account, name: 'Outro', agent_type: 'custom')
    described_class.create!(account: account, conversation: conversa, agent: outro, id_cotacao: 'c-outro',
                            planos: [{ 'codigo' => 'P1' }], pedido: {})

    expect(described_class.ultima_da_conversa(conversa.id, agente.id)).to eq(deste)
    expect(described_class.ultima_da_conversa(conversa.id, outro.id).id_cotacao).to eq('c-outro')
  end

  it 'plano pelo código; código desconhecido é nil' do
    c = criar_cotacao(planos: [{ 'codigo' => 'P1', 'preco_total' => '312.45' }])
    expect(c.plano('P1')['preco_total']).to eq('312.45')
    expect(c.plano('P9')).to be_nil
  end

  it 'do dia no fuso da conta' do
    fuso = ActiveSupport::TimeZone['America/Sao_Paulo']
    travel_to(Time.utc(2026, 11, 25, 2, 0)) do # 24/11 23h em São Paulo
      c = criar_cotacao
      expect(c.do_dia?(fuso)).to be(true)
    end
  end

  it 'idades vêm dos nossos parâmetros, não do pedido da Universal' do
    c = criar_cotacao(pedido: { 'idades' => [47, 19, 12], 'universal' => { 'passageiros' => [] } })
    expect(c.idades).to eq([47, 19, 12])
  end
end

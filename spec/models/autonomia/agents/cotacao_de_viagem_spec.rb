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

  describe '.da_mesma_viagem (#3223)' do
    let(:fuso) { ActiveSupport::TimeZone['America/Sao_Paulo'] }
    let(:viagem) do
      { 'destinos' => %w[PT ES], 'data_saida' => '2027-01-15', 'data_retorno' => '2027-01-20', 'idades' => [40, 38, 10],
        'motivo' => nil }
    end

    def mesma(pedido)
      described_class.da_mesma_viagem(conversa.id, agente.id, pedido, fuso: fuso)
    end

    it 'a de hoje com a mesma viagem; os destinos em qualquer ordem; o nome dos países e o pedido da Universal não contam' do
      travel_to(Time.utc(2026, 11, 26, 12, 0)) do
        cotacao = criar_cotacao(pedido: viagem.merge('destinos_nomes' => %w[Portugal Espanha], 'universal' => { 'x' => 1 }))
        expect(mesma(viagem.merge('destinos' => %w[ES PT]))).to eq(cotacao)
      end
    end

    it 'motivo vazio é o mesmo que sem motivo' do
      travel_to(Time.utc(2026, 11, 26, 12, 0)) do
        cotacao = criar_cotacao(pedido: viagem)
        expect(mesma(viagem.merge('motivo' => ''))).to eq(cotacao)
      end
    end

    it 'outra viagem não serve: outra data, idades em outra ordem, outro motivo' do
      travel_to(Time.utc(2026, 11, 26, 12, 0)) do
        criar_cotacao(pedido: viagem)
        expect(mesma(viagem.merge('data_retorno' => '2027-01-21'))).to be_nil
        expect(mesma(viagem.merge('idades' => [10, 38, 40]))).to be_nil
        expect(mesma(viagem.merge('motivo' => 'estudo'))).to be_nil
      end
    end

    it 'a de ontem no fuso da conta não serve, mesmo que no UTC seja o mesmo dia' do
      travel_to(Time.utc(2026, 11, 26, 2, 0)) { criar_cotacao(pedido: viagem) } # 25/11 23h em São Paulo
      travel_to(Time.utc(2026, 11, 26, 4, 0)) { expect(mesma(viagem)).to be_nil } # 26/11 1h em São Paulo
    end

    it 'com mais de uma, a mais nova' do
      travel_to(Time.utc(2026, 11, 26, 12, 0)) do
        criar_cotacao(pedido: viagem)
        nova = criar_cotacao(pedido: viagem)
        expect(mesma(viagem)).to eq(nova)
      end
    end

    it 'só a última da conversa: A, B e de novo A não devolve a 1ª A (a proposta lê a última)' do
      travel_to(Time.utc(2026, 11, 26, 12, 0)) do
        criar_cotacao(pedido: viagem)
        criar_cotacao(pedido: viagem.merge('idades' => [40]))
        expect(mesma(viagem)).to be_nil
      end
    end
  end

  it 'idades vêm dos nossos parâmetros, não do pedido da Universal' do
    c = criar_cotacao(pedido: { 'idades' => [47, 19, 12], 'universal' => { 'passageiros' => [] } })
    expect(c.idades).to eq([47, 19, 12])
  end
end

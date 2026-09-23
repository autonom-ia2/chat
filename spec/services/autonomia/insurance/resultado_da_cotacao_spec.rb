require 'rails_helper'

# A LEITURA POR PRODUTO (23/09/2026, conversa 7057): com auto e residencial na mesma conversa, cada leitura acha a
# cotação do seu produto, e quem pergunta "alguma corre?" enxerga as duas. Dados sintéticos.
RSpec.describe Autonomia::Insurance::ResultadoDaCotacao do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end

  def cotacao(faixa:, status:, criada:, handle: { 'quote_id' => 'q-1' })
    Autonomia::Agents::ToolRun.create!(account: account, agent: agent, slug: described_class.cotacao.slug, status: status,
                                       conversation_id: conversation.id, execution_key: SecureRandom.uuid,
                                       arguments: {}, handle: handle, created_at: criada, faixa: faixa)
  end

  it 'com a faixa, lê a execução daquele produto; sem ela, a mais nova da conversa' do
    auto = cotacao(faixa: 'auto', status: 'done', criada: 2.hours.ago)
    casa = cotacao(faixa: 'residencial', status: 'done', criada: 1.hour.ago)

    expect(described_class.da_conversa(conversation.id, faixa: 'auto').run).to eq(auto)
    expect(described_class.da_conversa(conversation.id).run).to eq(casa)
    expect(described_class.ultimas_cotadas(conversation.id, ramo: 'auto')).to eq([auto])
  end

  it 'a que corre é achada mesmo quando a mais nova já fechou' do
    carro = cotacao(faixa: 'auto', status: 'running', criada: 2.hours.ago)
    cotacao(faixa: 'residencial', status: 'done', criada: 1.hour.ago)

    expect(described_class.correndo_na_conversa(conversation.id).run).to eq(carro)
  end

  it 'a que corre com o portal já fechado não conta como correndo' do
    cotacao(faixa: 'auto', status: 'running', criada: 1.hour.ago,
            handle: { 'quote_id' => 'q-1', described_class.cotacao::FECHADO_KEY => true })

    expect(described_class.correndo_na_conversa(conversation.id)).to be_nil
  end

  it 'lista os produtos com cotação que conta, do mais novo ao mais antigo' do
    cotacao(faixa: 'auto', status: 'done', criada: 3.hours.ago)
    cotacao(faixa: 'residencial', status: 'running', criada: 2.hours.ago)
    cotacao(faixa: 'bike', status: 'superseded', criada: 1.hour.ago)

    expect(described_class.produtos(conversation.id)).to eq(%w[residencial auto])
  end

  # POR BEM (chat#612): dois carros e um apartamento na mesma conversa.
  describe 'a escolha do bem' do
    let(:especialista) { instance_double(Autonomia::Agents::Specialist) }

    before do
      allow(Autonomia::Insurance::QuoteAgent::Builder).to receive(:ramo_do_especialista).and_return(nil)
      allow(Autonomia::Insurance::QuoteAgent::Builder).to receive(:ramo_do_especialista).with(especialista).and_return('auto')
      cotacao(faixa: 'auto:nivus fvu2f42', status: 'done', criada: 3.hours.ago)
      cotacao(faixa: 'auto:onix abc1d23', status: 'done', criada: 2.hours.ago)
      cotacao(faixa: 'residencial:apartamento paulista', status: 'done', criada: 1.hour.ago)
    end

    def escolha(params, quem = nil, exigir: false)
      described_class.escolha(conversation.id, params, quem, exigir: exigir)
    end

    it 'o nome exato do bem lê aquele bem, sem pergunta' do
      expect(escolha({ 'produto' => ' Auto:Nivus  FVU2F42 ' }).to_h).to eq(faixa: 'auto:nivus fvu2f42', pergunta: nil)
    end

    it 'só o ramo lê o bem quando ele é o único do ramo' do
      expect(escolha({ 'produto' => 'residencial' }).faixa).to eq('residencial:apartamento paulista')
    end

    it 'só o ramo com dois bens pergunta qual, listando os do ramo' do
      resultado = escolha({ 'produto' => 'auto' })

      expect(resultado.faixa).to be_nil
      expect(resultado.pergunta).to include('auto:onix abc1d23; auto:nivus fvu2f42')
      expect(resultado.pergunta).not_to include('residencial')
    end

    it 'o que não casa com nada pergunta, com a lista inteira, em vez de dizer que não há cotação' do
      resultado = escolha({ 'produto' => 'carro' })

      expect(resultado.faixa).to be_nil
      expect(resultado.pergunta).to include('residencial:apartamento paulista; auto:onix abc1d23; auto:nivus fvu2f42')
    end

    it 'sem nada dito, o ramo do especialista decide, pela mesma regra' do
      expect(escolha({}, especialista).pergunta).to include('auto:onix abc1d23')
    end

    it 'o especialista de um ramo sem bem na conversa lê o ramo, e não pergunta pelos bens dos outros ramos' do
      de_bike = instance_double(Autonomia::Agents::Specialist)
      allow(Autonomia::Insurance::QuoteAgent::Builder).to receive(:ramo_do_especialista).with(de_bike).and_return('bike')

      expect(escolha({}, de_bike).to_h).to eq(faixa: 'bike', pergunta: nil)
    end

    it 'sem nada dito e sem especialista, a mais nova; a leitura que exige o bem pergunta' do
      expect(escolha({}).to_h).to eq(faixa: nil, pergunta: nil)
      expect(escolha({}, exigir: true).pergunta).to include('Esta conversa tem cotação de:')
    end

    it 'as bases de recotação são uma por bem do ramo' do
      cotacao(faixa: 'auto:nivus fvu2f42', status: 'done', criada: 30.minutes.ago)

      bases = described_class.ultimas_cotadas(conversation.id, ramo: 'auto')

      expect(bases.map(&:faixa)).to eq(['auto:nivus fvu2f42', 'auto:onix abc1d23'])
      expect(bases.first.created_at).to be > 1.hour.ago
    end
  end
end

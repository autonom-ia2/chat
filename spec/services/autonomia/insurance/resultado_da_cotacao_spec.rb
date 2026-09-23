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
    expect(described_class.ultima_cotada(conversation.id, faixa: 'auto')).to eq(auto)
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

  it 'o produto pedido vence o do especialista, e o do especialista vale quando não há pedido' do
    especialista = instance_double(Autonomia::Agents::Specialist)
    allow(Autonomia::Insurance::QuoteAgent::Builder).to receive(:ramo_do_especialista).and_return(nil)
    allow(Autonomia::Insurance::QuoteAgent::Builder).to receive(:ramo_do_especialista).with(especialista).and_return('residencial')

    expect(described_class.produto_pedido({ 'produto' => ' Auto ' }, especialista)).to eq('auto')
    expect(described_class.produto_pedido({ 'produto' => nil }, especialista)).to eq('residencial')
    expect(described_class.produto_pedido({}, nil)).to be_nil
  end
end

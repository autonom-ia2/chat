require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:atendente) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let!(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end
  let(:planos) do
    [{ 'codigo' => 'P1', 'nome' => 'Especial UA 100K BRL', 'preco_total' => '360.0', 'max_parcelas' => 12,
       'idade_minima' => 0, 'idade_maxima' => 65,
       'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '120.0', 'valor_moeda' => '120.0' }],
       'coberturas' => [{ 'id_beneficio' => 2898, 'nome' => 'Despesas Médicas', 'valor' => 'R$ 100.000', 'moeda' => 'BRL' }] }]
  end
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: contratado, id_cotacao: 'c-1', planos: planos,
      pedido: { 'destinos' => ['BR'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [47, 19, 12],
                'motivo' => nil, 'universal' => {} }
    )
  end
  let(:marcador) { "content_attributes::text LIKE '%autonomia_comparativo_viagem%'" }

  before do
    enable_test_encryption!
    Autonomia::Agents::AgentInbox.create!(agent: contratado, inbox: inbox, account: account, agent_bot: agent_bot)
  end

  around { |example| with_modified_env(AUTONOMIA_AGENTS_ENABLED: 'true') { example.run } }

  it 'posta o PDF uma vez por cotação, sem texto' do
    2.times { described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado) }
    mensagens = conversa.messages.where(marcador)
    expect(mensagens.count).to eq(1)
    expect(mensagens.first.content).to be_nil
    expect(mensagens.first.attachments.first.file.content_type).to eq('application/pdf')
  end

  it 'com responsável na conversa vira nota privada, e a nota também conta para não repetir (R7)' do
    conversa.update!(assignee: atendente)
    2.times { described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado) }
    expect(conversa.messages.last.private).to be(true)
    expect(conversa.messages.where(marcador).count).to eq(1)
  end

  it 'sem responsável é pública, e a pública também conta para não repetir (R7)' do
    2.times { described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado) }
    expect(conversa.messages.where(marcador).pluck(:private)).to eq([false])
  end

  it 'outra cotação da mesma conversa posta o seu PDF' do
    outra = Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: contratado,
                                                       id_cotacao: 'c-2', planos: planos, pedido: cotacao.pedido)
    [cotacao, outra].each { |item| described_class.postar(conversation: conversa, cotacao: item, agent: contratado) }
    expect(conversa.messages.where(marcador).count).to eq(2)
  end

  it 'falha não levanta' do
    allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_raise(StandardError)
    expect(described_class.postar(conversation: conversa, cotacao: cotacao, agent: contratado)).to be(false)
  end
end

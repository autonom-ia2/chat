require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
  let(:atendente) { create(:user, account: account) }
  let(:agent_bot) { create(:agent_bot, account: account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
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
  let(:atributos) { { 'autonomia_agent_id' => contratado.id, 'autonomia_cartao_token' => 'mensagem:1:cartao:comparativo_viagem:1' } }

  def postar
    described_class.new(conversation: conversa, cotacao: cotacao, sender_id: agent_bot.id, atributos: atributos).postar!
  end

  before { enable_test_encryption! }

  it 'o cartão do turno: o tipo e o id da cotação, sem formato' do
    expect(described_class.cartao(cotacao)).to eq('tipo' => 'comparativo_viagem', 'chave' => cotacao.id.to_s, 'rich_message' => nil)
    expect(described_class.cartao?(described_class.cartao(cotacao))).to be(true)
    expect(described_class.cartao?('tipo' => 'location')).to be(false)
  end

  it 'a cotação do cartão só nesta conversa' do
    cartao = described_class.cartao(cotacao)
    expect(described_class.cotacao_do(cartao, conversa)).to eq(cotacao)
    expect(described_class.cotacao_do(cartao, create(:conversation, account: account, inbox: inbox))).to be_nil
  end

  it 'posta o PDF anexado, sem texto, com o marcador da cotação e os atributos do cartão' do
    mensagem = postar
    expect(mensagem.content).to be_nil
    expect(mensagem.private).to be(false)
    expect(mensagem.sender).to eq(agent_bot)
    expect(mensagem.attachments.sole.file.content_type).to eq('application/pdf')
    expect(mensagem.content_attributes).to include(atributos.merge(described_class::CHAVE => cotacao.id))
  end

  it 'com responsável na conversa vira nota privada' do
    conversa.update!(assignee: atendente)
    expect(postar.private).to be(true)
  end

  it 'erro ao gerar o PDF sobe (quem registra é o EnviarCartoesJob), sem mensagem' do
    desenho = instance_double(Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf)
    allow(Autonomia::Agents::Tools::Native::SeguroViagem::ComparativoPdf).to receive(:new).and_return(desenho)
    allow(desenho).to receive(:render).and_raise(Prawn::Errors::CannotFit)
    expect { postar }.to raise_error(Prawn::Errors::CannotFit)
    expect(conversa.messages.count).to eq(0)
  end

  it 'erro ao criar a mensagem apaga o arquivo e sobe' do
    allow(Messages::MessageBuilder).to receive(:new).and_raise(ActiveRecord::StatementInvalid)
    expect { postar }.to raise_error(ActiveRecord::StatementInvalid)
    expect(ActiveStorage::Blob.count).to eq(0)
  end
end

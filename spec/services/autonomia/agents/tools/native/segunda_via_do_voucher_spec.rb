require 'rails_helper'

# #3246: a segunda via do voucher, só com o pagamento feito e pelo carrinho da proposta guardada. Dados fictícios.
RSpec.describe Autonomia::Agents::Tools::Native::SegundaViaDoVoucher do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:proposta) { { 'codigo_do_plano' => 'P1', 'codigo_carrinho' => 987_654, 'link' => 'https://pagamento.exemplo.test/' } }
  let!(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: contratado, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: proposta)
  end
  let(:voucher) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher }

  before do
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
  end

  def universal(status)
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 200, body: { 'statusPagamento' => status }.to_json)
  end

  def pedir(argumentos = {}, entrega: delivery)
    described_class.new(agent: contratado, params: argumentos, delivery: entrega).call
  end

  it 'pago: marca o cartão do voucher' do
    universal('Pago')
    expect(JSON.parse(pedir)).to eq('voucher_vai_junto' => true)
    expect(delivery.cartoes).to eq([voucher.cartao(cotacao)])
  end

  it 'pago e voucher já enviado antes: a segunda via sai de novo' do
    cotacao.update!(proposta: proposta.merge('voucher_enviado_em' => 1.day.ago.iso8601))
    universal('Pago')
    pedir
    expect(delivery.cartoes).to eq([voucher.cartao(cotacao)])
  end

  it 'aguardando: recusa com o motivo, sem cartão' do
    universal('Aguardando Pagamento')
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pagamento_pendente', anything)
    expect(pedir).to eq(described_class::TEXTO_PENDENTE)
    expect(delivery.cartoes).to be_empty
  end

  it 'cancelado: recusa com o motivo, sem cartão' do
    universal('Cancelado')
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pagamento_cancelado', anything)
    expect(pedir).to eq(described_class::TEXTO_CANCELADO)
    expect(delivery.cartoes).to be_empty
  end

  it 'sem proposta: recusa sem chamar a Universal' do
    cotacao.update!(proposta: nil)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_proposta', anything)
    pedir
    expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
  end

  it 'o carrinho é sempre o da proposta guardada, nunca o do modelo' do
    stub = universal('Pago')
    pedir('carrinho' => '111')
    expect(stub).to have_been_requested.once
    expect(a_request(:get, "#{base}/v1/StatusPagamento/111")).not_to have_been_made
  end

  it 'sem conversa não consulta' do
    expect(pedir(entrega: nil)).to include('pagamento_sem_conversa')
  end

  it 'a Universal recusa o acesso: passa pelas falhas, sem cartão' do
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 401, body: '')
    expect(pedir).to eq(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas::TEXTO_PASSAR)
    expect(delivery.cartoes).to be_empty
  end

  it 'pedido inválido da Universal vira indisponível' do
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 404, body: '')
    expect(pedir).to eq(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas::TEXTO_INDISPONIVEL)
  end

  it 'escreve (manda arquivo ao cliente)' do
    expect(described_class.escreve?).to be(true)
  end
end

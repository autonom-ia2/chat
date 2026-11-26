require 'rails_helper'

# #3246: a Bia confere o pagamento pela proposta guardada da conversa. Dados fictícios.
RSpec.describe Autonomia::Agents::Tools::Native::SituacaoDoPagamento do
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
  let!(:cotacao) { cotacao_com(proposta) }
  let(:voucher) { Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoVoucher }

  before do
    enable_test_encryption!
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok')
  end

  def cotacao_com(guardada)
    Autonomia::Agents::CotacaoDeViagem.create!(account: account, conversation: conversa, agent: contratado, id_cotacao: 'c-1',
                                               planos: [], pedido: { 'idades' => [45] }, proposta: guardada)
  end

  def universal(status, data: nil, carrinho: 987_654)
    stub_request(:get, "#{base}/v1/StatusPagamento/#{carrinho}")
      .to_return(status: 200, body: { 'statusPagamento' => status, 'dataPagamento' => data }.to_json)
  end

  def conferir(argumentos = {}, entrega: delivery)
    JSON.parse(described_class.new(agent: contratado, params: argumentos, delivery: entrega).call)
  end

  it 'pago: devolve a situação e a data, marca o cartão do voucher e grava pago_em' do
    universal('Pago', data: '2026-11-26T11:53:08.773')
    expect(conferir).to eq('situacao' => 'pago', 'data_do_pagamento' => '26/11/2026', 'voucher_vai_junto' => true)
    expect(delivery.cartoes).to eq([voucher.cartao(cotacao)])
    expect(cotacao.reload.proposta).to include('pago_em' => '2026-11-26T11:53:08.773', 'codigo_carrinho' => 987_654)
  end

  it 'pago com o voucher já enviado nesta cotação: não marca de novo (o automático é uma vez)' do
    cotacao.update!(proposta: proposta.merge('voucher_enviado_em' => 1.hour.ago.iso8601, 'pago_em' => '2026-11-26T11:47:40'))
    universal('Pago', data: '2026-11-26T11:47:40')
    expect(conferir).to include('situacao' => 'pago', 'voucher_vai_junto' => false)
    expect(delivery.cartoes).to be_empty
  end

  it 'pago_em fica o primeiro visto' do
    cotacao.update!(proposta: proposta.merge('pago_em' => '2026-11-26T11:47:40'))
    universal('Pago', data: '2026-11-27T09:00:00')
    conferir
    expect(cotacao.reload.proposta['pago_em']).to eq('2026-11-26T11:47:40')
  end

  it 'pago sem data da Universal: grava a hora em que viu, e a data ao modelo fica nil' do
    universal('Pago')
    expect(conferir['data_do_pagamento']).to be_nil
    expect(cotacao.reload.proposta['pago_em']).to be_present
  end

  ['Aguardando Pagamento', '', 'Valor Novo'].each do |status|
    it "#{status.inspect}: aguardando, sem voucher e sem pago_em" do
      universal(status)
      expect(conferir).to eq('situacao' => 'aguardando', 'data_do_pagamento' => nil, 'voucher_vai_junto' => false)
      expect(delivery.cartoes).to be_empty
      expect(cotacao.reload.proposta).not_to have_key('pago_em')
    end
  end

  it 'cancelado: sem voucher' do
    universal('Cancelado')
    expect(conferir).to include('situacao' => 'cancelado', 'voucher_vai_junto' => false)
    expect(delivery.cartoes).to be_empty
  end

  it 'o carrinho é sempre o da proposta guardada, nunca o do modelo' do
    stub = universal('Aguardando Pagamento')
    conferir({ 'carrinho' => '111', 'codigo_carrinho' => 111, 'numero_do_carrinho' => '111' })
    expect(stub).to have_been_requested.once
    expect(a_request(:get, "#{base}/v1/StatusPagamento/111")).not_to have_been_made
  end

  it 'cotação mais nova sem proposta: confere a proposta da anterior (o cliente pagou e cotou outra viagem)' do
    cotacao_com(nil)
    stub = universal('Aguardando Pagamento')
    conferir
    expect(stub).to have_been_requested.once
  end

  it 'sem proposta na conversa: recusa sem chamar a Universal' do
    cotacao.update!(proposta: nil)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_proposta', anything)
    described_class.new(agent: contratado, params: {}, delivery: delivery).call
    expect(a_request(:get, "#{base}/v1/StatusPagamento/987654")).not_to have_been_made
  end

  it 'sem conversa não consulta' do
    expect(described_class.new(agent: contratado, params: {}, delivery: nil).call).to include('pagamento_sem_conversa')
  end

  it 'a Universal fora passa pelas falhas (tenta uma vez de novo), sem marcar nada' do
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 500, body: '')
    texto = described_class.new(agent: contratado, params: {}, delivery: delivery).call
    expect(texto).to eq(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas::TEXTO_INDISPONIVEL)
    expect(delivery.cartoes).to be_empty
  end

  it 'pedido inválido da Universal vira indisponível (não há dado do cliente a corrigir)' do
    stub_request(:get, "#{base}/v1/StatusPagamento/987654").to_return(status: 400, body: '{"message":"curta"}')
    texto = described_class.new(agent: contratado, params: {}, delivery: delivery).call
    expect(texto).to eq(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas::TEXTO_INDISPONIVEL)
  end

  it 'proposta guardada sem carrinho não conta: confere a anterior, que tem' do
    cotacao_com({ 'link' => 'https://pagamento.exemplo.test/' })
    stub = universal('Aguardando Pagamento')
    conferir
    expect(stub).to have_been_requested.once
  end

  it 'escreve (marca o cartão do voucher) e não tem parâmetro' do
    expect(described_class.escreve?).to be(true)
    expect(described_class.openai_schema[:parameters][:properties]).to eq({})
  end
end

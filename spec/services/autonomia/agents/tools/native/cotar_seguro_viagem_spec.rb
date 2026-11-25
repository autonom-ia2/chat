require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::CotarSeguroViagem do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => marca })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:params) do
    { 'destinos' => ['pt'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45], 'motivo' => nil }
  end

  before do
    enable_test_encryption!
    travel_to Time.utc(2026, 11, 24, 15, 0, 0)
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok',
                                                  capacidades: { 'tarifa_acordo' => true })
    stub_request(:get, "#{base}/v1/destinos").to_return(status: 200, body: file_fixture('../universal/destinos.json').read)
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: file_fixture('../universal/cotacao.json').read)
    allow(Autonomia::Agents::Tools::Native::SeguroViagem::EntregaDoComparativo).to receive(:postar).and_return(true)
  end

  def ferramenta(argumentos)
    described_class.new(agent: contratado, params: argumentos, delivery: delivery)
  end

  it 'cota, guarda e devolve só o resumo' do
    saida = JSON.parse(ferramenta(params).call)
    esperado = [
      { 'codigo' => 'P1', 'nome' => 'Especial UA 100K BRL', 'preco_total' => 'R$ 360,00', 'max_parcelas' => 12,
        'principais' => { 'despesas_medicas' => 'R$ 100.000', 'bagagem' => 'R$ 2.000', 'cancelamento' => 'R$ 2.500' } },
      { 'codigo' => 'P2', 'nome' => 'Especial UA 30K BRL', 'preco_total' => 'R$ 210,00', 'max_parcelas' => 12,
        'principais' => { 'despesas_medicas' => 'R$ 30.000', 'bagagem' => 'R$ 1.000', 'cancelamento' => nil } }
    ]
    expect(saida['planos']).to eq(esperado)
    expect(saida['pdf_enviado']).to be(true)
    cotacao = Autonomia::Agents::CotacaoDeViagem.last
    expect(cotacao.id_cotacao).to eq('COT-TESTE-1')
    expect(cotacao.pedido.except('universal')).to eq('destinos' => ['PT'], 'destinos_nomes' => ['Portugal'],
                                                     'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06',
                                                     'idades' => [45], 'motivo' => nil)
    expect(cotacao.pedido['universal']['passageiros']).to eq([{ 'nome' => 'Viajante 1', 'dataNascimento' => '1981-08-02' }])
    expect(cotacao.idades).to eq([45])
    expect(a_request(:post, "#{base}/v1/Cotacao").with(body: hash_including('tipoTarifa' => 2, 'classificacoes' => [1]))).to have_been_made
  end

  it 'devolve a viagem conferida e nenhum campo interno da seguradora (R2)' do
    texto = ferramenta(params).call
    expect(JSON.parse(texto)['cotacao']).to eq('destinos' => ['PT'], 'data_saida' => '2027-02-02',
                                               'data_retorno' => '2027-02-06', 'idades' => [45])
    %w[comissao markup rank quotationPorcentagem valorSemDesconto].each { |campo| expect(texto).not_to include(campo) }
    expect(Autonomia::Agents::CotacaoDeViagem.last.planos.to_json).not_to include('comissao', 'markup', 'rank')
  end

  it 'sem conversa não cota' do
    expect(described_class.new(agent: contratado, params: params, delivery: nil).call).to include('cotacao_sem_conversa')
    expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
  end

  it 'data errada recusa com o campo e registra a recusa (não trava a escrita do turno)' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pedido_invalido', hash_including(faltando: ['data_saida']))
    ferramenta(params.merge('data_saida' => '2020-01-01')).call
  end

  it 'destino que a seguradora não atende: recusa sem cotar' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('destino_invalido', hash_including(faltando: ['destinos']))
    expect(ferramenta(params.merge('destinos' => %w[PT XX])).call).to include('XX')
    expect(a_request(:post, "#{base}/v1/Cotacao")).not_to have_been_made
  end

  it 'idade que nenhum plano aceita: idade_fora_do_limite' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('idade_fora_do_limite', hash_including(faltando: ['idades']))
    ferramenta(params.merge('idades' => [70])).call
  end

  it 'resposta sem plano: sem_plano, e nada é guardado' do
    stub_request(:post, "#{base}/v1/Cotacao").to_return(status: 200, body: { 'idCotacao' => 'c-0', 'produtos' => [] }.to_json)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_plano', anything)
    ferramenta(params).call
    expect(Autonomia::Agents::CotacaoDeViagem.count).to eq(0)
  end

  it 'timeout não levanta e passa pelas falhas' do
    stub_request(:post, "#{base}/v1/Cotacao").to_timeout
    expect(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas).to receive(:tratar)
      .with(an_instance_of(Autonomia::Seguradoras::Universal::Cliente::Erro), acao: 'cotar_seguro_viagem',
                                                                              agent: contratado, conversation: conversa).and_call_original
    expect { ferramenta(params).call }.not_to raise_error
  end
end

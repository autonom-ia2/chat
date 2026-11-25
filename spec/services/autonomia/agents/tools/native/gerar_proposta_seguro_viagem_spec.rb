require 'rails_helper'

# Dados fictícios: o CPF tem dígito verificador válido e não é de ninguém conhecido.
RSpec.describe Autonomia::Agents::Tools::Native::GerarPropostaSeguroViagem do
  let(:base) { 'https://api-br.universal-assistance.com' }
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox) }
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato',
                                     config: { 'contratado' => { 'modelo' => 'seguro_viagem_universal' } })
  end
  let(:delivery) { Autonomia::Agents::Tools::Delivery.new(conversation: conversa, agent_inbox: nil) }
  let(:acesso) do
    Autonomia::Agents::AcessoDaSeguradora.create!(account: account, agent: contratado, login: 'corretor.teste',
                                                  senha: 's3nha-teste', estado: 'ok',
                                                  capacidades: { 'tarifa_acordo' => true })
  end
  let(:resposta) { JSON.parse(file_fixture('../universal/cotacao.json').read) }
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.create!(
      account: account, conversation: conversa, agent: contratado, id_cotacao: 'COT-TESTE-1',
      planos: Autonomia::Agents::Tools::Native::SeguroViagem::Planos.de(resposta, idades: [45]),
      pedido: { 'destinos' => ['PT'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45],
                'motivo' => nil, 'universal' => { 'tipoTarifa' => 2 } }
    )
  end
  let(:plano) { cotacao.plano('P1') }
  let(:titular) do
    { 'nome_completo' => 'Fulano de Teste', 'cpf' => '529.982.247-25', 'data_nascimento' => '1981-03-15',
      'email' => 'fulano@exemplo.test', 'telefone' => '(11) 98765-4321', 'cep' => '01310-100', 'numero' => '1000',
      'complemento' => nil }
  end
  let(:params) do
    { 'codigo_do_plano' => 'P1', 'titular' => titular, 'demais_viajantes' => [],
      'contato_de_emergencia' => { 'nome' => 'Beltrana de Teste', 'telefone' => '11912345678' } }
  end
  let(:endereco) do
    { 'logradouro' => 'Avenida Exemplo', 'bairro' => 'Centro', 'cidade' => 'São Paulo', 'uf' => 'SP', 'cep' => '01310100' }
  end

  before do
    enable_test_encryption!
    travel_to Time.utc(2026, 11, 24, 15, 0, 0)
    acesso
    cotacao
    allow(Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep).to receive(:buscar).and_return(endereco)
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 200, body: file_fixture('../universal/compras_ok.json').read)
  end

  def ferramenta(argumentos, entrega: delivery)
    described_class.new(agent: contratado, params: argumentos, delivery: entrega)
  end

  def params_com_titular_nascido_em(data)
    params.merge('titular' => titular.merge('data_nascimento' => data))
  end

  it 'preço e produto saem da cotação guardada' do
    ferramenta(params).call
    da_cotacao = lambda do |requisicao|
      corpo = JSON.parse(requisicao.body)
      corpo['DadosBasicos']['ValorCompra'].to_d == BigDecimal(plano['preco_total']) &&
        corpo['DadosProdutos']['CodigoProduto'] == plano['id_produto'] && corpo['DadosBasicos']['FormaPagamento'] == 8
    end
    expect(a_request(:post, "#{base}/v1/Compras").with(&da_cotacao)).to have_been_made.once
  end

  it 'preço e produto mandados pelo modelo não entram na compra' do
    ferramenta(params.merge('preco_total' => '1.00', 'ValorCompra' => 1, 'id_produto' => 1, 'CodigoProduto' => 1)).call
    da_cotacao = lambda do |requisicao|
      corpo = JSON.parse(requisicao.body)
      basicos, produtos = corpo.values_at('DadosBasicos', 'DadosProdutos')
      basicos['ValorCompra'].to_d == 360 && produtos['ValorProduto'].to_d == 360 &&
        produtos['CodigoProduto'] == 5_382_451 && produtos['CodigoTarifaAcordo'] == 634_248
    end
    expect(a_request(:post, "#{base}/v1/Compras").with(&da_cotacao)).to have_been_made.once
  end

  it 'devolve o link montado do codigoCarrinho' do
    expect(JSON.parse(ferramenta(params).call)['link_de_pagamento'])
      .to eq('https://pagamento.universal-assistance.com/?IdCarrinho=987654')
  end

  it 'devolve ao modelo só o link, o carrinho, o plano e o total' do
    expect(JSON.parse(ferramenta(params).call))
      .to eq('link_de_pagamento' => 'https://pagamento.universal-assistance.com/?IdCarrinho=987654',
             'numero_do_carrinho' => 987_654, 'plano' => 'Especial UA 100K BRL', 'total' => 'R$ 360,00')
  end

  it 'idempotente: a mesma chamada não gera segunda proposta' do
    2.times { ferramenta(params).call }
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.once
  end

  it 'idempotente: a segunda chamada devolve a mesma proposta' do
    primeira = ferramenta(params).call
    expect(ferramenta(params.merge('codigo_do_plano' => ' p1 ')).call).to eq(primeira)
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.once
  end

  it 'outro plano é outra proposta' do
    ferramenta(params).call
    ferramenta(params.merge('codigo_do_plano' => 'P2')).call
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.twice
    expect(cotacao.reload.proposta['codigo_do_plano']).to eq('P2')
  end

  it 'código inexistente recusa sem chamar a Universal' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('plano_inexistente', hash_including(faltando: ['codigo_do_plano']))
    ferramenta(params.merge('codigo_do_plano' => 'P9')).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'faixa mudou: recotar, registrado (não conta como escrita feita)' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('recotar', hash_including(faltando: ['idades']))
    ferramenta(params_com_titular_nascido_em('1960-01-10')).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'cotação de ontem: recotar' do
    cotacao.update!(created_at: 2.days.ago)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('recotar', anything)
    ferramenta(params).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'acesso que só cota não gera' do
    acesso.update!(capacidades: acesso.capacidades.merge('so_cotacao' => true))
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('so_cotacao', anything)
    ferramenta(params).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'sem cotação na conversa recusa' do
    Autonomia::Agents::CotacaoDeViagem.delete_all
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('sem_cotacao', anything)
    ferramenta(params).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'sem conversa não gera' do
    expect(ferramenta(params, entrega: nil).call).to include('proposta_sem_conversa')
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'CPF inválido recusa com o campo, sem chamar a Universal' do
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('pedido_invalido', hash_including(faltando: ['titular.cpf']))
    ferramenta(params.merge('titular' => titular.merge('cpf' => '5299822472'))).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'viajantes a mais que os da cotação: recusa a quantidade' do
    outro = { 'nome_completo' => 'Ciclana de Teste', 'cpf' => '111.444.777-35', 'data_nascimento' => '2014-07-01' }
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('quantidade_de_viajantes', anything)
    ferramenta(params.merge('demais_viajantes' => [outro])).call
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'endereço que não sai pelo CEP: recusa sem afirmar CEP errado' do
    allow(Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep).to receive(:buscar).and_return(nil)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('cep_nao_encontrado', hash_including(faltando: ['titular.cep']))
    expect(ferramenta(params).call).to include('Confirme o CEP')
    expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
  end

  it 'CEP único sem logradouro e bairro: a compra sai com eles nulos (R17)' do
    allow(Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep).to receive(:buscar)
      .and_return('cep' => '01310100', 'cidade' => 'São Paulo', 'uf' => 'SP')
    ferramenta(params).call
    sem_rua = lambda do |requisicao|
      titular = JSON.parse(requisicao.body)['DadosTitular']
      titular['Endereco'].nil? && titular['Bairro'].nil? && titular['Cidade'] == 'São Paulo'
    end
    expect(a_request(:post, "#{base}/v1/Compras").with(&sem_rua)).to have_been_made.once
  end

  it 'compra sem codigoCarrinho: passa pelas falhas (sem link)' do
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 200, body: { codigoCarrinho: nil }.to_json)
    expect(Autonomia::Agents::Tools::Native::SeguroViagem::Falhas).to receive(:sem_link)
      .with(acao: 'gerar_proposta_seguro_viagem', agent: contratado, conversation: conversa).and_call_original
    ferramenta(params).call
    expect(cotacao.reload.proposta).to be_nil
  end

  it 'a seguradora recusa o pedido: passa pelas falhas e nada fica guardado' do
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 400, body: file_fixture('../universal/compras_400.json').read)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('pedido_invalido', anything)
    expect(ferramenta(params).call).to include('A seguradora não aceitou o pedido')
    expect(cotacao.reload.proposta).to be_nil
  end

  it 'proposta guardada não tem dado pessoal' do
    ferramenta(params).call
    expect(cotacao.reload.proposta.to_json).not_to include('52998224725', 'Fulano', '@')
  end

  it 'o log não leva dado pessoal' do
    linhas = []
    allow(Rails.logger).to receive(:info) { |texto| linhas << texto.to_s }
    allow(Rails.logger).to receive(:warn) { |texto| linhas << texto.to_s }
    ferramenta(params).call
    expect(linhas.join("\n")).not_to include('52998224725', 'Fulano', 'fulano@exemplo.test', '987654321', 'Beltrana')
  end
end

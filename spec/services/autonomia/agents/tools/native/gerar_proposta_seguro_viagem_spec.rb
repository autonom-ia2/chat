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
        corpo['DadosProdutos']['CodigoProduto'] == plano['id_produto'] && corpo['DadosBasicos']['FormaPagamento'] == 7
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

  it 'devolve o urlVoucher da compra como link (#3244)' do
    expect(JSON.parse(ferramenta(params).call)['link_de_pagamento'])
      .to eq('https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA==')
  end

  # A regra do P1 na fixture: multa 0 até 2026-11-24T00:00 (meia-noite), ou seja, até o fim de 23/11, que já passou no
  # dia da proposta (24/11): sem prazo para o cliente (#3246).
  it 'devolve ao modelo só o link, o carrinho, o plano, o total e até quando cancela sem custo' do
    expect(JSON.parse(ferramenta(params).call))
      .to eq('link_de_pagamento' => 'https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA==',
             'numero_do_carrinho' => 987_654, 'plano' => 'Especial UA 100K BRL', 'total' => 'R$ 360,00',
             'cancelamento_sem_custo_ate' => nil)
  end

  # #3246: no JSON compacto o link grudava no campo seguinte (`...==","numero_do_carrinho"`), e o botão de link nunca o
  # reconhecia entre os endereços da saída da ferramenta.
  it 'o link de pagamento sai separado por espaço, e o botão de link o reconhece na saída' do
    saida = ferramenta(params).call
    expect(Autonomia::Agents::Interacao::Enderecos.dos_textos([saida]))
      .to include('https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA==')
    expect(Autonomia::Agents::Interacao::Enderecos.do_dono(dono: ['Pague em https://pagamento.universal-assistance.com'],
                                                           ferramentas: [saida]))
      .to include('https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA==')
  end

  describe 'cancelamento_sem_custo_ate' do
    def com_regra(regra)
      planos = cotacao.planos.map { |guardado| guardado['codigo'] == 'P1' ? guardado.merge('regra_cancelamento' => regra) : guardado }
      cotacao.update!(planos: planos)
      JSON.parse(ferramenta(params).call)['cancelamento_sem_custo_ate']
    end

    it 'o maior "ate" sem multa; meia-noite vale até o fim do dia anterior' do
      regra = [{ 'de' => '2026-11-24T00:00:00', 'ate' => '2026-12-02T00:00:00', 'multa' => 0, 'geraCredito' => false },
               { 'de' => '2026-12-02T00:00:00', 'ate' => '2027-01-31T00:00:00', 'multa' => 50, 'geraCredito' => false }]
      expect(com_regra(regra)).to eq('01/12/2026')
    end

    it '"ate" fora da meia-noite vale o próprio dia' do
      expect(com_regra([{ 'ate' => '2026-12-02T18:00:00-03:00', 'multa' => 0 }])).to eq('02/12/2026')
    end

    it 'dia que já passou não é prazo: nil' do
      expect(com_regra([{ 'ate' => '2026-11-23T18:00:00', 'multa' => 0 }])).to be_nil
      expect(com_regra([{ 'ate' => '2026-11-25T00:00:00', 'multa' => 0 }])).to eq('24/11/2026')
    end

    it 'sem faixa sem multa, ou sem regra: nil' do
      expect(com_regra([{ 'ate' => '2026-12-02T00:00:00', 'multa' => 30 }])).to be_nil
      expect(com_regra([{ 'ate' => '2026-12-02T00:00:00', 'multa' => nil }])).to be_nil
      expect(com_regra([])).to be_nil
    end
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

  it 'dado corrigido é outra proposta: o segundo POST devolve o link novo' do
    link_novo = 'https://pagamento.universal-assistance.com/?IdCarrinho=b3V0cm8tY2FycmluaG8='
    segunda = JSON.parse(file_fixture('../universal/compras_ok.json').read)
                  .merge('codigoCarrinho' => 987_655, 'urlVoucher' => link_novo)
    stub_request(:post, "#{base}/v1/Compras")
      .to_return({ status: 200, body: file_fixture('../universal/compras_ok.json').read }, { status: 200, body: segunda.to_json })
    ferramenta(params).call
    corrigida = ferramenta(params.merge('titular' => titular.merge('email' => 'fulano.novo@exemplo.test'))).call
    expect(JSON.parse(corrigida)['link_de_pagamento']).to eq(link_novo)
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.twice
  end

  it 'repetição idêntica depois de vencer o link (24 h na Universal) gera carrinho e link novos' do
    link_novo = 'https://pagamento.universal-assistance.com/?IdCarrinho=bm92by1saW5r'
    segunda = JSON.parse(file_fixture('../universal/compras_ok.json').read)
                  .merge('codigoCarrinho' => 987_655, 'urlVoucher' => link_novo)
    stub_request(:post, "#{base}/v1/Compras")
      .to_return({ status: 200, body: file_fixture('../universal/compras_ok.json').read }, { status: 200, body: segunda.to_json })
    ferramenta(params).call
    # A cotação só vale no dia (`do_dia?`): quem envelhece aqui é só a proposta guardada.
    vencida = cotacao.reload.proposta.merge('gerada_em' => (23.hours + 1.minute).ago.iso8601)
    cotacao.update!(proposta: vencida)
    expect(JSON.parse(ferramenta(params).call)['link_de_pagamento']).to eq(link_novo)
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.twice
  end

  it 'repetição idêntica devolve o link guardado sem buscar o CEP (fonte de CEP fora)' do
    primeira = ferramenta(params).call
    expect(Autonomia::Agents::Tools::Native::SeguroViagem::EnderecoDoCep).not_to receive(:buscar)
    expect(ferramenta(params).call).to eq(primeira)
    expect(a_request(:post, "#{base}/v1/Compras")).to have_been_made.once
  end

  it 'a chave guardada não é o hash simples dos CPFs nem leva o segredo cru' do
    ferramenta(params).call
    chave = cotacao.reload.proposta['chave']
    expect(chave).not_to eq(Digest::SHA256.hexdigest([cotacao.id, 'P1', ['52998224725']].join('|')))
    expect(chave).not_to eq(OpenSSL::HMAC.hexdigest('SHA256', Rails.application.secret_key_base,
                                                    [cotacao.id, 'P1', ['52998224725']].join('|')))
    expect(chave.length).to eq(64)
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

  it 'plano sem preço guardado: recusa como inexistente, sem chamar a Universal' do
    sem_preco = cotacao.planos.map { |item| item['codigo'] == 'P1' ? item.merge('preco_total' => nil) : item }
    cotacao.update!(planos: sem_preco)
    expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar)
      .with('plano_inexistente', hash_including(faltando: ['codigo_do_plano']))
    ferramenta(params).call
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

  [ActiveRecord::LockWaitTimeout, ActiveRecord::QueryCanceled].each do |estouro|
    it "espera do lock estourada (#{estouro.name.demodulize}): recusa nomeada, sem POST" do
      allow(Autonomia::Agents::CotacaoDeViagem).to receive(:ultima_da_conversa).and_return(cotacao)
      allow(cotacao).to receive(:lock!).and_raise(estouro)
      expect(Autonomia::Agents::Tools::Recusa).to receive(:registrar).with('proposta_em_andamento', anything)
      expect(ferramenta(params).call).to eq(described_class::TEXTO_EM_ANDAMENTO)
      expect(a_request(:post, "#{base}/v1/Compras")).not_to have_been_made
      expect(cotacao.reload.proposta).to be_nil
    end
  end

  it 'tempo do banco estourado depois de travar (já na compra) não vira proposta_em_andamento' do
    allow(Autonomia::Agents::CotacaoDeViagem).to receive(:ultima_da_conversa).and_return(cotacao)
    allow(cotacao).to receive(:update!).and_raise(ActiveRecord::QueryCanceled)
    expect(Autonomia::Agents::Tools::Recusa).not_to receive(:registrar).with('proposta_em_andamento', anything)
    expect { ferramenta(params).call }.to raise_error(ActiveRecord::QueryCanceled)
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

  it 'compra com carrinho e sem urlVoucher: passa pelas falhas (sem link), não monta link pelo número (#3244)' do
    stub_request(:post, "#{base}/v1/Compras").to_return(status: 200, body: { codigoCarrinho: 987_654 }.to_json)
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

  it 'o log não leva dado pessoal (debug, info, warn e error; texto e bloco)' do
    linhas = []
    %i[debug info warn error].each do |nivel|
      allow(Rails.logger).to receive(nivel).and_wrap_original do |_original, *args, &bloco|
        linhas.concat(args.map(&:to_s))
        linhas << bloco&.call.to_s
        true
      end
    end
    ferramenta(params).call
    pessoais = ['52998224725', 'Fulano', 'fulano@exemplo.test', '987654321', 'Beltrana', '11912345678']
    expect(linhas.join("\n")).not_to include(*pessoais)
  end
end

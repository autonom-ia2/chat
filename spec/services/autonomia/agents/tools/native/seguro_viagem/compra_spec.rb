require 'rails_helper'

# Dados fictícios: o CPF tem dígito verificador válido e não é de ninguém conhecido.
RSpec.describe Autonomia::Agents::Tools::Native::SeguroViagem::Compra do
  let(:cotacao) do
    Autonomia::Agents::CotacaoDeViagem.new(
      id_cotacao: 'COT-TESTE-1', planos: [plano],
      pedido: { 'destinos' => ['PT'], 'data_saida' => '2027-02-02', 'data_retorno' => '2027-02-06', 'idades' => [45, 12],
                'motivo' => nil, 'universal' => { 'tipoTarifa' => 2 } }
    )
  end
  let(:plano) do
    { 'codigo' => 'P1', 'id_produto' => 5_382_451, 'id_produto_acordo' => 634_248, 'nome' => 'Especial UA 100K BRL',
      'preco_total' => '360.0', 'cambio' => 5.9702, 'idade_minima' => 0, 'idade_maxima' => 65,
      'faixas' => [{ 'de' => 0, 'ate' => 65, 'valor' => '180.0' }] }
  end
  let(:viajantes) do
    [{ 'nome_completo' => 'Fulano de Teste Silva', 'cpf' => '52998224725', 'nascimento' => Date.new(1981, 3, 15),
       'email' => 'fulano@exemplo.test', 'telefone' => '11987654321', 'cep' => '01310100', 'numero' => '1000',
       'complemento' => nil },
     { 'nome_completo' => 'Ciclana de Teste', 'cpf' => '11144477735', 'nascimento' => Date.new(2014, 7, 1) }]
  end
  let(:endereco) { { 'cep' => '01310100', 'cidade' => 'São Paulo', 'uf' => 'SP' } }
  let(:contato) { { 'nome' => 'Beltrana de Teste', 'telefone' => '11912345678' } }
  let(:compra) do
    described_class.montar(cotacao: cotacao, plano: plano, viajantes: viajantes, endereco: endereco, contato: contato)
  end

  it 'preço, produto, tarifa e datas saem da cotação guardada' do
    basicos = compra['DadosBasicos']
    expect(basicos.slice('FormaPagamento', 'ValorCompra', 'TipoTarifa', 'DataSaida', 'DataRetorno', 'Destinos', 'TipoViagem'))
      .to eq('FormaPagamento' => 7, 'ValorCompra' => 360.0, 'TipoTarifa' => 2, 'DataSaida' => '2027-02-02',
             'DataRetorno' => '2027-02-06', 'Destinos' => ['PT'], 'TipoViagem' => 1)
    expect(compra['DadosProdutos'])
      .to eq('CodigoProduto' => 5_382_451, 'ValorProduto' => 360.0, 'CodigoPeriodoMultiViagem' => 0,
             'CodigoTarifaAcordo' => 634_248, 'Cambio' => 5.9702)
  end

  it 'o titular vai com a data de nascimento informada, a idade na saída e o contato de emergência' do
    titular = compra['DadosTitular']
    expect(titular.slice('Codigo', 'Nome', 'Sobrenome', 'Documento', 'TipoDocumento', 'DataNascimento', 'Idade'))
      .to eq('Codigo' => 1, 'Nome' => 'Fulano', 'Sobrenome' => 'de Teste Silva', 'Documento' => '52998224725',
             'TipoDocumento' => 1, 'DataNascimento' => '1981-03-15', 'Idade' => 45)
    expect(compra['DadosBasicos'].slice('NomeContatoBrasil', 'TelefoneContatoBrasil', 'CelularContatoBrasil'))
      .to eq('NomeContatoBrasil' => 'Beltrana de Teste', 'TelefoneContatoBrasil' => '11912345678',
             'CelularContatoBrasil' => '11912345678')
    expect(compra['DadosPagamento']).to eq('NomeTitularCartao' => 'Fulano de Teste Silva', 'CPFTitular' => '52998224725')
  end

  it 'os demais viajantes vão como integrantes a partir do código 2' do
    expect(compra['DadosIntegrantes'])
      .to eq([{ 'Codigo' => 2, 'Nome' => 'Ciclana', 'Sobrenome' => 'de Teste', 'TipoDocumento' => 1,
                'Documento' => '11144477735', 'DataNascimento' => '2014-07-01', 'Idade' => 12 }])
    expect(compra.values_at('DadosBeneficios', 'DadosBeneficiosCustomizavel', 'DadosProdutosAvulsos')).to eq([[], [], []])
  end

  it 'CEP de cidade com CEP único: monta com logradouro e bairro nulos (R17)' do
    titular = compra['DadosTitular']
    expect(titular.slice('Endereco', 'Bairro', 'Cidade', 'UF', 'CEP', 'Numero', 'SiglaPaisEndereco', 'Complemento'))
      .to eq('Endereco' => nil, 'Bairro' => nil, 'Cidade' => 'São Paulo', 'UF' => 'SP', 'CEP' => '01310100',
             'Numero' => '1000', 'SiglaPaisEndereco' => 'BR', 'Complemento' => nil)
  end

  it 'com logradouro e bairro, vão no endereço' do
    completo = endereco.merge('logradouro' => 'Avenida Exemplo', 'bairro' => 'Centro')
    titular = described_class.montar(cotacao: cotacao, plano: plano, viajantes: viajantes, endereco: completo,
                                     contato: contato)['DadosTitular']
    expect(titular.slice('Endereco', 'Bairro')).to eq('Endereco' => 'Avenida Exemplo', 'Bairro' => 'Centro')
  end

  it 'preço do plano: BigDecimal do texto guardado; nil sem preço ou fora de número' do
    expect(described_class.preco(plano)).to eq(BigDecimal('360.0'))
    expect(described_class.preco(plano.merge('preco_total' => nil))).to be_nil
    expect(described_class.preco(plano.merge('preco_total' => ''))).to be_nil
    expect(described_class.preco(plano.merge('preco_total' => 'abc'))).to be_nil
    %w[NaN Infinity -Infinity 0 0.0 -5].each do |invalido|
      expect(described_class.preco(plano.merge('preco_total' => invalido))).to be_nil
    end
  end

  # #3244: o link com o número cru do carrinho abre "Carrinho não encontrado"; vale o `urlVoucher` da compra.
  it 'link de pagamento é o urlVoucher da compra, no host de pagamento' do
    url = 'https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA=='
    expect(described_class.link(" #{url} ")).to eq(url)
  end

  it 'recusa urlVoucher fora do host de pagamento, sem https, sem carrinho ou inválido' do
    ['https://pagamento.exemplo.com/?IdCarrinho=abc', 'http://pagamento.universal-assistance.com/?IdCarrinho=abc',
     'https://pagamento.universal-assistance.com/', 'https://[/?IdCarrinho=abc',
     'https://x@pagamento.universal-assistance.com/?IdCarrinho=abc',
     'https://pagamento.universal-assistance.com:8443/?IdCarrinho=abc',
     987_654, nil, ''].each { |url| expect(described_class.link(url)).to be_nil }
  end

  # A proposta guardada na cotação, da resposta da compra (era `GerarPropostaSeguroViagem#proposta_da`; saiu dela no
  # #3263, só pelo tamanho da ferramenta).
  it 'proposta guardada: a chave, o plano, o carrinho, o link e a hora, sem o valor da resposta' do
    travel_to Time.utc(2026, 11, 24, 15, 0, 0) do
      resposta = JSON.parse(file_fixture('../universal/compras_ok.json').read)
      expect(described_class.proposta(resposta, plano: plano, chave: 'k'))
        .to eq('chave' => 'k', 'codigo_do_plano' => 'P1', 'codigo_carrinho' => 987_654,
               'link' => 'https://pagamento.universal-assistance.com/?IdCarrinho=c2VtLWRhZG8tcmVhbA==',
               'gerada_em' => '2026-11-24T15:00:00Z')
    end
  end

  it 'proposta guardada: nil sem link de pagamento válido ou com resposta que não é objeto' do
    [{ 'codigoCarrinho' => 987_654 }, { 'urlVoucher' => 'https://pagamento.exemplo.com/?IdCarrinho=abc' }, [], nil]
      .each { |resposta| expect(described_class.proposta(resposta, plano: plano, chave: 'k')).to be_nil }
  end
end

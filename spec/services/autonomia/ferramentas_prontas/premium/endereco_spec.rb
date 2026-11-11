require 'rails_helper'

# #2858 (F7) com a regra "QI 70" do Rodrigo (11/11): a ferramenta deduz sozinha o dado técnico que dá para deduzir. No
# risco do endereço, o cliente não precisa saber o CEP: a criminalidade aceita a cidade e a UF, e a área de risco e a
# vistoria aceitam a rua, o número e a cidade. O CEP vem de um método único (`Premium::Endereco.cep`), que a branch da
# QI 70 liga ao CEP de referência da cidade e à consulta cep/por_endereco. Aqui ele é dublado. Zero chamada real.
RSpec.describe Autonomia::FerramentasProntas::Premium::Endereco do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:risco) { incluir_pronta('risco_endereco', conta: account, agente: agent) }
  let(:crimes) do
    { 'City' => 'SAO PAULO', 'State' => 'SP', 'TotalLast360DaysOccurrences' => 100,
      'CriminalOccurrencesByNature' => [{ 'CriminalNature' => 'FURTO', 'Last360DaysOccurrences' => 60 }] }
  end

  around { |example| com_credencial_da_bigdatacorp { example.run } }

  before do
    ligar_premium(account)
    cache_em_memoria
    token_da_bigdatacorp
  end

  def pediu(rota, busca)
    a_request(:post, "#{FerramentasPremiumHelper::BDC}#{rota}").with(body: hash_including('q' => busca))
  end

  # A `Fontes::Cep::Referencia` é da branch da QI 70 (fix/2858-qi70-prontas), ainda não juntada: aqui ela é dublada com
  # a assinatura que aquela branch promete (fef3ca2c47). Depois do merge o dublê troca a de verdade, e o spec segue valendo.
  describe 'o método único delega ao CEP de referência da QI 70' do
    let(:interface) do
      Module.new do
        def self.cep(cidade:, uf: nil, rua: nil, bairro: nil, conta: nil); end # rubocop:disable Naming/MethodParameterName
      end
    end
    let(:referencia) { stub_const('Autonomia::FerramentasProntas::Fontes::Cep::Referencia', interface) }

    before { allow(referencia).to receive(:cep).and_return(nil) }

    it 'passa a cidade, a UF, a rua, o bairro e a conta' do
      described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: 'Sé', conta: 42)

      expect(referencia).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: 'Sé', conta: 42)
    end

    it 'devolve o CEP só com os dígitos, como a BigDataCorp recebe' do
      allow(referencia).to receive(:cep).and_return('cep' => '01001-000')

      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP')).to eq('cep' => '01001000')
    end

    it 'devolve os candidatos como vieram, para o agente perguntar o bairro' do
      candidatos = [{ 'cep' => '01001-000', 'logradouro' => 'Rua EXEMPLO', 'complemento' => '', 'bairro' => 'Sé' }]
      allow(referencia).to receive(:cep).and_return('candidatos' => candidatos)

      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Rua EXEMPLO')).to eq('candidatos' => candidatos)
    end

    it 'sem CEP achado, nil (o agente pede o CEP)' do
      expect(described_class.cep(cidade: 'Cidade EXEMPLO', uf: 'SP')).to be_nil
    end

    it 'CEP que não tem 8 dígitos não serve: nil' do
      allow(referencia).to receive(:cep).and_return('cep' => '0100')

      expect(described_class.cep(cidade: 'São Paulo', uf: 'SP')).to be_nil
    end
  end

  describe 'criminalidade pela cidade e a UF' do
    it 'acha o CEP de referência da cidade e consulta por ele' do
      allow(described_class).to receive(:cep).and_return('cep' => '01001000')
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'São Paulo', 'uf' => 'sp')

      expect(resposta['situacao']).to eq('encontrado')
      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: nil, bairro: nil, conta: account.id)
      expect(pediu('/enderecos', 'zipcode{01001000}')).to have_been_made.once
    end

    it 'sem CEP achado, pede o CEP e não chama a BigDataCorp' do
      allow(described_class).to receive(:cep).and_return(nil)
      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Cidade EXEMPLO', 'uf' => 'sp')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'cep')
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'com o CEP, segue como antes, sem procurar' do
      allow(described_class).to receive(:cep)
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      expect(executar_premium(risco, 'consulta' => 'criminalidade', 'cep' => '01001-000')['situacao']).to eq('encontrado')
      expect(described_class).not_to have_received(:cep)
    end

    it 'sem CEP e sem cidade, pede o CEP' do
      expect(executar_premium(risco, 'consulta' => 'criminalidade')).to include('situacao' => 'pedido_invalido', 'campo' => 'cep')
    end
  end

  describe 'área de risco e vistoria pelo endereço' do
    it 'acha o CEP pela rua e a cidade e consulta com o número' do
      allow(described_class).to receive(:cep).and_return('cep' => '01001000')
      bigdatacorp_responde('/enderecos', 'address_risk', 'AddressRiskData', { 'Point' => 3 })

      resposta = executar_premium(risco, 'consulta' => 'area_de_risco', 'rua' => 'Praça da Sé', 'numero' => '10', 'cidade' => 'São Paulo',
                                         'uf' => 'sp')

      expect(resposta['situacao']).to eq('encontrado')
      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: nil, conta: account.id)
      expect(pediu('/enderecos', 'zipcode{01001000},addressnumber{10}')).to have_been_made.once
    end

    it 'com mais de um CEP para a rua, pergunta o bairro e não chama a BigDataCorp' do
      allow(described_class).to receive(:cep).and_return('candidatos' => %w[01001000 01002000])

      resposta = executar_premium(risco, 'consulta' => 'vistoria', 'rua' => 'Rua EXEMPLO', 'numero' => '10', 'cidade' => 'São Paulo',
                                         'uf' => 'sp')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'bairro')
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'com o bairro, o bairro vai junto na procura' do
      allow(described_class).to receive(:cep).and_return('cep' => '01001000')
      bigdatacorp_responde('/marketplace', 'partner_rede_vistorias_address', 'RedeVistoriasData', { 'Tipology' => 'CASA' })

      executar_premium(risco, 'consulta' => 'vistoria', 'rua' => 'Rua EXEMPLO', 'numero' => '10', 'bairro' => 'Sé', 'cidade' => 'São Paulo',
                              'uf' => 'sp')

      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Rua EXEMPLO', bairro: 'Sé', conta: account.id)
    end

    it 'o número continua obrigatório: ele não dá para deduzir' do
      allow(described_class).to receive(:cep)

      resposta = executar_premium(risco, 'consulta' => 'area_de_risco', 'rua' => 'Praça da Sé', 'cidade' => 'São Paulo', 'uf' => 'sp')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'numero')
      expect(described_class).not_to have_received(:cep)
    end

    it 'a cidade, a UF, a rua e o bairro não vão à BigDataCorp nem ao cache: só o CEP e o número' do
      consulta = Autonomia::FerramentasProntas::Catalogo.buscar('risco_endereco').consulta('area_de_risco')

      expect(consulta.para_a_fonte('cep' => '01001000', 'numero' => '10', 'cidade' => 'São Paulo', 'uf' => 'sp', 'rua' => 'x', 'bairro' => 'y'))
        .to eq('cep' => '01001000', 'numero' => '10')
    end
  end

  describe 'o que a instrução diz ao agente' do
    let(:catalogo) { Autonomia::FerramentasProntas::Catalogo }

    it 'empresas na região: o número é da região do CEP; pede a rua ou o bairro, sem usar o CEP geral da cidade sem avisar' do
      descricao = catalogo.buscar('contato_empresa').consulta('empresas_na_regiao').descricao

      expect(descricao).to include('da região do CEP', 'peça a rua ou o bairro', 'CEP geral da cidade')
    end

    it 'imóvel rural: diz onde achar o código, no recibo do CAR' do
      expect(catalogo.buscar('imovel_rural').consulta('car').descricao).to include('no recibo do CAR')
    end
  end
end

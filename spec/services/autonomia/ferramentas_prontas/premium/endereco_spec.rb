require 'rails_helper'

# #2858 (F7) com a regra "QI 70" do Rodrigo (11/11): a ferramenta deduz sozinha o dado técnico que dá para deduzir. No
# risco do endereço, o cliente não precisa saber o CEP: a criminalidade aceita a cidade (a UF é opcional), e a área de
# risco e a vistoria aceitam a rua, o número e a cidade. O CEP vem de um método único (`Premium::Endereco.cep`), ligado
# ao CEP de referência da cidade e à consulta cep/por_endereco da QI 70 (#2906). Zero chamada real: o ViaCEP e a
# BigDataCorp vêm do WebMock.
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

  describe 'o método único delega ao CEP de referência da QI 70' do
    let(:referencia) { Autonomia::FerramentasProntas::Fontes::Cep::Referencia }

    before { allow(referencia).to receive(:cep).and_return(nil) }

    it 'passa a cidade, a UF, a rua, o bairro e a conta' do
      described_class.cep(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: 'Sé', numero: '10', conta: 42)

      expect(referencia).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: 'Sé', numero: '10',
                                                     conta: 42)
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

  describe 'criminalidade pela cidade (a UF é opcional)' do
    it 'acha o CEP de referência da cidade e consulta por ele' do
      allow(described_class).to receive(:cep).and_return('cep' => '01001000')
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'São Paulo', 'uf' => 'sp')

      expect(resposta['situacao']).to eq('encontrado')
      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: nil, bairro: nil, numero: nil, conta: account.id)
      expect(pediu('/enderecos', 'zipcode{01001000}')).to have_been_made.once
    end

    it 'sem CEP achado, pede o CEP e não chama a BigDataCorp' do
      allow(described_class).to receive(:cep).and_return(nil)
      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Uberlândia', 'uf' => 'mg')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'cep')
      expect(resposta['orientacao']).to include('Não pergunte ao cliente', 'mande a cidade')
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'sem a UF: a cidade única no Brasil basta, e a UF vai nil à procura do CEP' do
      allow(described_class).to receive(:cep).and_return('cep' => '38400263')
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Uberlândia')

      expect(resposta['situacao']).to eq('encontrado')
      expect(described_class).to have_received(:cep).with(cidade: 'Uberlândia', uf: nil, rua: nil, bairro: nil, numero: nil, conta: account.id)
    end

    it 'a UF pelo nome do estado vira a sigla' do
      allow(described_class).to receive(:cep).and_return('cep' => '38400263')
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Uberlândia', 'uf' => 'Minas Gerais')

      expect(described_class).to have_received(:cep).with(cidade: 'Uberlândia', uf: 'MG', rua: nil, bairro: nil, numero: nil, conta: account.id)
    end

    it 'cidade com o mesmo nome em mais de um estado e sem UF: recusa na uf, com as candidatas, sem procurar nem cobrar' do
      allow(described_class).to receive(:cep)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Bom Jesus')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'uf')
      expect(resposta['candidatos']).to include('PI', 'RS')
      expect(described_class).not_to have_received(:cep)
      expect(chamou_a_bigdatacorp?).to be(false)
      expect(registros_premium).to be_empty
    end

    it 'cidade que não existe: recusa na cidade, sem procurar' do
      allow(described_class).to receive(:cep)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Cidade EXEMPLO')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'cidade')
      expect(described_class).not_to have_received(:cep)
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
      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Praça da Sé', bairro: nil, numero: '10',
                                                          conta: account.id)
      expect(pediu('/enderecos', 'zipcode{01001000},addressnumber{10}')).to have_been_made.once
    end

    it 'com mais de um CEP para a rua, recusa no bairro com os CEPs em candidatos e não chama a BigDataCorp' do
      candidatos = [{ 'cep' => '01001-000', 'bairro' => 'Sé' }, { 'cep' => '01002-000', 'bairro' => 'Centro' }]
      allow(described_class).to receive(:cep).and_return('candidatos' => candidatos)

      resposta = executar_premium(risco, 'consulta' => 'vistoria', 'rua' => 'Rua EXEMPLO', 'numero' => '10', 'cidade' => 'São Paulo',
                                         'uf' => 'sp')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'bairro', 'candidatos' => candidatos)
      expect(resposta['orientacao']).to include('pergunte ao cliente o bairro', 'As opções estão em "candidatos".')
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'com o bairro, o bairro vai junto na procura' do
      allow(described_class).to receive(:cep).and_return('cep' => '01001000')
      bigdatacorp_responde('/marketplace', 'partner_rede_vistorias_address', 'RedeVistoriasData', { 'Tipology' => 'CASA' })

      executar_premium(risco, 'consulta' => 'vistoria', 'rua' => 'Rua EXEMPLO', 'numero' => '10', 'bairro' => 'Sé', 'cidade' => 'São Paulo',
                              'uf' => 'sp')

      expect(described_class).to have_received(:cep).with(cidade: 'São Paulo', uf: 'SP', rua: 'Rua EXEMPLO', bairro: 'Sé', numero: '10',
                                                          conta: account.id)
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

  # Antes da QI 70 nesta branch, a `Fontes::Cep::Referencia` não existia e o pedido sem CEP dava NameError (virava "não
  # consegui"). Aqui nada é dublado do nosso lado: a procura vai de verdade ao helper da QI 70, e só o ViaCEP e a
  # BigDataCorp vêm do WebMock.
  describe 'sem CEP, de ponta a ponta com o CEP de referência da QI 70' do
    let(:uberlandia) { 'https://viacep.com.br/ws/MG/Uberlandia/Rua/json/' }
    let(:paulista) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Avenida%20Paulista/json/' }
    let(:de_sp) { { logradouro: 'Avenida Paulista', localidade: 'São Paulo', uf: 'SP', ibge: '3550308' } }

    before { resolver_hosts_das_prontas }

    def rua_de_uberlandia(cep)
      { cep: cep, logradouro: 'Rua EXEMPLO', bairro: 'Centro', localidade: 'Uberlândia', uf: 'MG', ibge: '3170206' }
    end

    it 'criminalidade só com a cidade: acha o CEP da cidade no ViaCEP e consulta a BigDataCorp por ele' do
      fonte_responde(uberlandia, [rua_de_uberlandia('38410-776'), rua_de_uberlandia('38400-263')])
      bigdatacorp_responde('/enderecos', 'criminal_statistics_data', 'CriminalStatisticsData', crimes)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Uberlândia')

      expect(resposta['situacao']).to eq('encontrado')
      expect(pediu('/enderecos', 'zipcode{38400263}')).to have_been_made.once
      expect(registros_premium.pluck(:resultado)).to eq(['encontrado'])
    end

    it 'área de risco pela rua com dois CEPs e um número fora das duas faixas: recusa no bairro, e a BigDataCorp não é chamada' do
      fonte_responde(paulista, [de_sp.merge(cep: '01310-100', complemento: 'de 1 a 609 - lado ímpar', bairro: 'Bela Vista'),
                                de_sp.merge(cep: '01311-000', complemento: 'de 611 a 1045', bairro: 'Cerqueira César')])

      resposta = executar_premium(risco, 'consulta' => 'area_de_risco', 'rua' => 'Avenida Paulista', 'numero' => '5000',
                                         'cidade' => 'São Paulo')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'bairro')
      expect(resposta['candidatos'].pluck('cep')).to eq(%w[01310-100 01311-000])
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'o bairro escolhe o CEP, e a consulta segue com ele e o número' do
      fonte_responde(paulista, [de_sp.merge(cep: '01310-100', bairro: 'Bela Vista'), de_sp.merge(cep: '01311-000', bairro: 'Cerqueira César')])
      bigdatacorp_responde('/enderecos', 'address_risk', 'AddressRiskData', { 'Point' => 3 })

      resposta = executar_premium(risco, 'consulta' => 'area_de_risco', 'rua' => 'Avenida Paulista', 'numero' => '700',
                                         'bairro' => 'Cerqueira César', 'cidade' => 'São Paulo')

      expect(resposta['situacao']).to eq('encontrado')
      expect(pediu('/enderecos', 'zipcode{01311000},addressnumber{700}')).to have_been_made.once
    end

    it 'ViaCEP fora: pede o CEP, e a BigDataCorp não é chamada nem cobrada' do
      fonte_fora(uberlandia)

      resposta = executar_premium(risco, 'consulta' => 'criminalidade', 'cidade' => 'Uberlândia')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'cep')
      expect(chamou_a_bigdatacorp?).to be(false)
      expect(registros_premium).to be_empty
    end
  end

  # C15c/C15d do testador, de ponta a ponta com os dados reais do ViaCEP (11/11/2026): com o bairro dito, o número escolhe
  # o CEP; sem o número, pede o número e não o bairro de novo.
  describe 'o bairro e o número escolhem o CEP da rua' do
    let(:augusta) { 'https://viacep.com.br/ws/SP/Sao%20Paulo/Rua%20Augusta/json/' }

    before do
      resolver_hosts_das_prontas
      fonte_responde(augusta, Rails.root.join('spec/fixtures/ferramentas_prontas/viacep_rua_augusta_sao_paulo.json').read)
    end

    it 'Rua Augusta, Consolação, nº 100: consulta pelo 01304-000 ("até 698 - lado par")' do
      bigdatacorp_responde('/enderecos', 'address_risk', 'AddressRiskData', { 'Point' => 3 })

      resposta = executar_premium(risco, 'consulta' => 'area_de_risco', 'rua' => 'Rua Augusta', 'numero' => '100', 'bairro' => 'Consolação',
                                         'cidade' => 'São Paulo')

      expect(resposta['situacao']).to eq('encontrado')
      expect(pediu('/enderecos', 'zipcode{01304000},addressnumber{100}')).to have_been_made.once
    end

    it 'empresas na região na Rua Augusta, Consolação, sem número: pede o NÚMERO, não o bairro, e não chama a BigDataCorp' do
      contato = incluir_pronta('contato_empresa', conta: account, agente: agent)

      resposta = executar_premium(contato, 'consulta' => 'empresas_na_regiao', 'rua' => 'Rua Augusta', 'bairro' => 'Consolação',
                                           'cidade' => 'São Paulo')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'numero')
      expect(resposta['orientacao']).to include('pergunte ao cliente o número do imóvel')
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'empresas na região pela rua, o bairro e o número: consulta pelo CEP da faixa (QI 70, sem pedir o CEP)' do
      contato = incluir_pronta('contato_empresa', conta: account, agente: agent)
      bigdatacorp_responde('/enderecos', 'companies_statistics', 'CompaniesStatistics', { 'TotalCompanies' => 1200 })

      resposta = executar_premium(contato, 'consulta' => 'empresas_na_regiao', 'rua' => 'Rua Augusta', 'numero' => '100',
                                           'bairro' => 'Consolação', 'cidade' => 'São Paulo')

      expect(resposta['situacao']).to eq('encontrado')
      expect(pediu('/enderecos', 'zipcode{01304000}')).to have_been_made.once
    end

    it 'empresas na região só com a cidade: pede a rua (a contagem é da região do CEP, não da cidade inteira)' do
      contato = incluir_pronta('contato_empresa', conta: account, agente: agent)
      allow(described_class).to receive(:cep)

      resposta = executar_premium(contato, 'consulta' => 'empresas_na_regiao', 'cidade' => 'São Paulo')

      expect(resposta).to include('situacao' => 'pedido_invalido', 'campo' => 'rua')
      expect(resposta['orientacao']).to include('pergunte ao cliente a rua', 'região do CEP')
      expect(described_class).not_to have_received(:cep)
      expect(chamou_a_bigdatacorp?).to be(false)
    end

    it 'empresas na região com o CEP segue direto, sem procurar' do
      contato = incluir_pronta('contato_empresa', conta: account, agente: agent)
      allow(described_class).to receive(:cep)
      bigdatacorp_responde('/enderecos', 'companies_statistics', 'CompaniesStatistics', { 'TotalCompanies' => 1200 })

      expect(executar_premium(contato, 'consulta' => 'empresas_na_regiao', 'cep' => '01304-000')['situacao']).to eq('encontrado')
      expect(described_class).not_to have_received(:cep)
    end
  end

  describe 'o que a instrução diz ao agente' do
    let(:catalogo) { Autonomia::FerramentasProntas::Catalogo }

    it 'empresas na região: o número é da região do CEP; sem o CEP, manda a rua e a cidade, e o CEP geral da cidade não serve' do
      consulta = catalogo.buscar('contato_empresa').consulta('empresas_na_regiao')

      expect(consulta.descricao).to include('da região do CEP', 'mande a rua e a cidade', 'CEP geral da cidade')
      expect(consulta.obrigatorios).to be_empty
      expect(consulta.parametros.map(&:nome)).to contain_exactly('cep', 'rua', 'numero', 'bairro', 'cidade', 'uf')
    end

    it 'imóvel rural: diz onde achar o código, no recibo do CAR' do
      expect(catalogo.buscar('imovel_rural').consulta('car').descricao).to include('no recibo do CAR')
    end
  end
end

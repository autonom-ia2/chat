require 'rails_helper'

# #2858 (F7): os 7 cards Premium, os datasets da BigDataCorp de cada um e os preços do plano aprovado (custo da 1ª faixa
# da documentação pública × 1,5). Mudou um preço ou um dataset, este spec quebra de propósito.
RSpec.describe Autonomia::FerramentasProntas::Catalogo, '.premium' do
  let(:catalogo) { described_class }
  let(:premium) { Autonomia::FerramentasProntas::Premium }

  # card => { consulta => [dataset, rota, custo, preço] }
  let(:tabela) do
    {
      'certidoes_empresa' => {
        'divida_uniao' => ['ondemand_pgfn_company', '/ondemand', '0.1', '0.15'],
        'trabalhista' => ['ondemand_cert_labor_debt_absence_company', '/ondemand', '0.1', '0.15'],
        'fgts' => ['ondemand_fgts_company', '/ondemand', '0.04', '0.06'],
        'cnj' => ['ondemand_cnj_negative_certificate_company', '/ondemand', '0.1', '0.15'],
        'cadin' => ['ondemand_cadin_company', '/ondemand', '0.1', '0.15']
      },
      'raio_x_empresa' => {
        'processos' => ['processes', '/empresas', '0.08', '0.12'],
        'sancoes' => ['kyc', '/empresas', '0.06', '0.09'],
        'crescimento' => ['company_evolution', '/empresas', '0.06', '0.09'],
        'grupo_economico' => ['economic_group_relationships', '/empresas', '0.06', '0.09'],
        'obras' => ['civil_construction_data', '/empresas', '0.06', '0.09']
      },
      'conferir_pessoa' => {
        'situacao_cpf' => ['ondemand_rf_status_person', '/ondemand', '0.06', '0.09'],
        'nome_e_nascimento' => ['basic_data', '/pessoas', '0.04', '0.06'],
        'conselho' => ['class_organization', '/pessoas', '0.06', '0.09']
      },
      'historico_placa' => { 'placa' => ['license_plates', '/veiculos', '0.06', '0.09'] },
      'risco_endereco' => {
        'area_de_risco' => ['address_risk', '/enderecos', '0.08', '0.12'],
        'criminalidade' => ['criminal_statistics_data', '/enderecos', '0.06', '0.09'],
        'vistoria' => ['partner_rede_vistorias_address', '/marketplace', '0.26', '0.39']
      },
      'imovel_rural' => {
        'car' => ['sicar_property_data', '/enderecos', '0.1', '0.15'],
        'embargo_ibama' => ['ondemand_ibama_embargados_company', '/ondemand', '0.15', '0.23']
      },
      'contato_empresa' => {
        'telefone' => ['phones_extended', '/empresas', '0.06', '0.09'],
        'email' => ['emails_extended', '/empresas', '0.06', '0.09'],
        'empresas_na_regiao' => ['companies_statistics', '/enderecos', '0.06', '0.09']
      }
    }
  end

  it 'tem os 7 cards, com os 22 datasets, os custos e os preços do plano' do
    cards = catalogo.premium
    expect(cards.map(&:chave)).to eq(tabela.keys)

    cards.each do |card|
      atual = card.consultas.to_h do |consulta|
        dataset = consulta.dataset
        [consulta.nome, [dataset.nome, dataset.rota, dataset.custo.to_s('F'), dataset.preco.to_s('F')]]
      end
      expect(atual).to eq(tabela.fetch(card.chave)), card.chave
    end
    expect(cards.sum { |card| card.consultas.size }).to eq(22)
  end

  it 'todo preço do catálogo fecha em centavos inteiros (o embargo do IBAMA, R$ 0,225, sobe para R$ 0,23)' do
    described_class.premium.flat_map(&:consultas).each do |consulta|
      centavos = consulta.dataset.preco * 100
      expect(centavos).to eq(centavos.to_i), consulta.nome
    end
  end

  it 'o preço de todo dataset é o custo × 1,5, arredondado para cima ao centavo' do
    catalogo.premium.flat_map(&:consultas).each do |consulta|
      expect(consulta.dataset.preco_confere?).to be(true), consulta.nome
    end
  end

  it 'todo card é Premium, da flag da F7, sem limite diário (decisão do Rodrigo) e com a BigDataCorp como host' do
    catalogo.premium.each do |card|
      expect(card).to be_premium
      expect(card.flag).to eq(premium::FLAG)
      expect(card.limite_diario).to be_nil
      expect(card.hosts).to eq(['plataforma.bigdatacorp.com.br'])
      expect(card.slug).to start_with('pronta_')
    end
    expect(catalogo.todas.reject(&:premium?).map(&:chave)).not_to include(*tabela.keys)
  end

  it 'as rotas de todos os datasets estão na lista do cliente da BigDataCorp' do
    rotas = catalogo.premium.flat_map(&:consultas).map { |consulta| consulta.dataset.rota }.uniq
    expect(Autonomia::Prospecting::Research::BigDataCorpClient::ROUTES).to include(*rotas)
  end

  it 'nenhum card tem parâmetro de contato, endereço ou parente de pessoa física (recusa por desenho do schema)' do
    parametros = catalogo.premium.flat_map { |card| card.consultas.flat_map(&:parametros).map(&:nome) }.uniq
    expect(parametros).to contain_exactly('cnpj', 'cpf', 'placa', 'cep', 'numero', 'codigo_car')

    contato = catalogo.buscar('contato_empresa')
    expect(contato.consultas.flat_map(&:parametros).map(&:nome).uniq).to contain_exactly('cnpj', 'cep')
    pessoa = catalogo.buscar('conferir_pessoa')
    expect(pessoa.consultas.map { |consulta| consulta.dataset.nome })
      .to contain_exactly('ondemand_rf_status_person', 'basic_data', 'class_organization')
  end

  it 'fora: score de crédito, contato de pessoa física, parentes, antecedentes, política, apostas, SUS e TSE' do
    datasets = catalogo.premium.flat_map(&:consultas).map { |consulta| consulta.dataset.nome }
    proibidos = %w[financial_risk credit_score collections phones emails addresses related_people family_relationships
                   criminal_records political_involvement electoral_donors online_gambling sus_data tse_data]
    expect(datasets & proibidos).to be_empty
  end

  it 'o schema do card de várias consultas pede a consulta pelo nome e aceita só os parâmetros do card' do
    schema = catalogo.buscar('certidoes_empresa').openai_schema(slug: 'pronta_certidoes_empresa', usar_quando: nil)
    propriedades = schema[:parameters][:properties]
    expect(propriedades['consulta']['enum']).to eq(%w[divida_uniao trabalhista fgts cnj cadin])
    expect(propriedades.keys).to contain_exactly('consulta', 'cnpj')
    expect(schema[:description]).to include('Consulta paga')
  end

  it 'as Premium não entram no Construtor nem no cartão "pode ganhar"' do
    conta = create(:account)
    ligar_premium(conta)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)

    expect(Autonomia::FerramentasProntas.disponiveis(conta).map(&:chave)).to include(*tabela.keys)
    expect(Autonomia::FerramentasProntas.sugeriveis(conta).map(&:chave)).not_to include(*tabela.keys)
    expect(Autonomia::FerramentasProntas.sugeriveis(conta).map(&:chave)).to include('cep', 'cpf')
  end

  it 'sem a flag do Premium, nenhum card fica disponível, e as grátis seguem' do
    conta = create(:account)
    conta.enable_features!(Autonomia::FerramentasProntas::FLAG)

    expect(Autonomia::FerramentasProntas.disponiveis(conta).map(&:chave)).to include('cep')
    expect(Autonomia::FerramentasProntas.disponiveis(conta).select(&:premium?)).to be_empty
  end
end

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

  # Os 22 datasets ficam no código, os 7 desligados na BigDataCorp também (#2946): eles voltam com uma linha.
  it 'tem os 7 cards, com os 22 datasets, os custos e os preços do plano' do
    cards = catalogo.premium
    expect(cards.map(&:chave)).to eq(tabela.keys)

    cards.each do |card|
      atual = consultas_do_card(card.chave).to_h do |consulta|
        dataset = consulta.dataset
        [consulta.nome, [dataset.nome, dataset.rota, dataset.custo.to_s('F'), dataset.preco.to_s('F')]]
      end
      expect(atual).to eq(tabela.fetch(card.chave)), card.chave
    end
    expect(todas_as_consultas_premium.size).to eq(22)
  end

  # #2946: teste direto na API (12/11/2026), 6 datasets sob demanda e a vistoria respondem -1203 DATASET DISABLED
  # TEMPORARILY. Eles saem da ferramenta, do selo de perguntas, da faixa de preço e do Experimente.
  describe 'as consultas desligadas na BigDataCorp' do
    let(:desligadas) do
      %w[ondemand_pgfn_company ondemand_cert_labor_debt_absence_company ondemand_fgts_company ondemand_cadin_company
         ondemand_rf_status_person ondemand_ibama_embargados_company partner_rede_vistorias_address]
    end

    it 'saem dos cards (sobram 15 consultas), e card nenhum fica vazio' do
      expect(premium::DESLIGADAS_NA_FONTE).to match_array(desligadas)
      ligadas = catalogo.premium.flat_map(&:consultas).map { |consulta| consulta.dataset.nome }

      expect(ligadas).not_to include(*desligadas)
      expect(ligadas.size).to eq(15)
      expect(catalogo.premium.map { |card| card.consultas.size }).to all(be_positive)
      expect(catalogo.premium.to_h { |card| [card.chave, card.consultas.map(&:nome)] }).to eq(
        'certidoes_empresa' => %w[cnj], 'raio_x_empresa' => %w[processos sancoes crescimento grupo_economico obras],
        'conferir_pessoa' => %w[nome_e_nascimento conselho], 'historico_placa' => %w[placa],
        'risco_endereco' => %w[area_de_risco criminalidade], 'imovel_rural' => %w[car],
        'contato_empresa' => %w[telefone email empresas_na_regiao]
      )
    end

    it 'a lista só tem dataset que existe no código: tirar a linha dele traz a consulta de volta' do
      expect(todas_as_consultas_premium.map { |consulta| consulta.dataset.nome }).to include(*premium::DESLIGADAS_NA_FONTE)
    end

    it 'a ferramenta do agente não aceita a consulta desligada' do
      certidoes = catalogo.buscar('certidoes_empresa')

      expect(certidoes.consulta('divida_uniao')).to be_nil
      expect(certidoes.consulta(nil).nome).to eq('cnj')
      expect(catalogo.buscar('risco_endereco').consulta('vistoria')).to be_nil
    end

    it 'as Certidões só com a do CNJ: o schema pede só o CNPJ, a descrição diz qual certidão sai e recusa as outras' do
      schema = catalogo.buscar('certidoes_empresa').openai_schema(slug: 'pronta_certidoes_empresa', usar_quando: nil)

      expect(schema[:parameters][:properties].keys).to eq(%w[cnpj])
      expect(schema[:description]).to include('Só tira esta certidão: improbidade administrativa (certidão do CNJ).',
                                              'Outra certidão não é tirada aqui: diga isso ao cliente',
                                              'Não consulta agora: dívida com a União (PGFN)', 'diga com educação')
    end

    it 'o imóvel rural só com o CAR deixa de aceitar o CNPJ e recusa o embargo do IBAMA com educação' do
      schema = catalogo.buscar('imovel_rural').openai_schema(slug: 'pronta_imovel_rural', usar_quando: nil)

      expect(schema[:parameters][:properties].keys).to eq(%w[codigo_car])
      expect(schema[:description]).to include('Responde só a: a situação do imóvel no Cadastro Ambiental Rural',
                                              'Não consulta agora: se a empresa tem área embargada pelo IBAMA')
    end

    it 'o risco do endereço recusa a vistoria com educação; o card sem nada desligado não ganha a frase' do
      risco = catalogo.buscar('risco_endereco').openai_schema(slug: 'pronta_risco_endereco', usar_quando: nil)
      placa = catalogo.buscar('historico_placa').openai_schema(slug: 'pronta_historico_placa', usar_quando: nil)

      expect(risco[:description]).to include('Não consulta agora: o tipo, a área e as notas da vistoria do imóvel')
      expect(placa[:description]).not_to include('Não consulta agora')
    end

    # Revisor (#2949): a lista pode pegar o único dataset de um card (a CNJ, o CAR, a placa). O card sai do catálogo
    # inteiro (vitrine, "Incluir" e turno), o resto segue, e os prazos derivados não quebram.
    it 'desligando a única consulta de um card, ele sai da vitrine e do agente, sem quebrar o resto' do
      conta = create(:account)
      ligar_premium(conta)
      agente = Autonomia::Agents::Agent.create!(account: conta, name: 'Bot EXEMPLO', agent_type: 'custom', status: :active,
                                                enabled: true, instruction: 'Atenda.')
      ferramenta = incluir_pronta('certidoes_empresa', conta: conta, agente: agente)
      desligar_na_fonte!([*premium::DESLIGADAS_NA_FONTE, 'ondemand_cnj_negative_certificate_company'])

      expect(catalogo.premium.map(&:chave)).not_to include('certidoes_empresa')
      expect(catalogo.buscar('certidoes_empresa')).to be_nil
      expect(Autonomia::FerramentasProntas.disponiveis(conta).map(&:chave)).not_to include('certidoes_empresa')
      expect(Autonomia::FerramentasProntas.no_turno?(ferramenta, agente)).to be(false)
      expect(catalogo.chaves).to include('certidoes_empresa')
      expect(premium.prazo_maximo).to eq(122)
    end

    it 'com tudo desligado, nenhum card fica, e o prazo derivado cai no da base' do
      desligar_na_fonte!(todas_as_consultas_premium.map { |consulta| consulta.dataset.nome })

      expect(catalogo.premium).to be_empty
      expect(premium.prazo_maximo).to eq(premium::Dataset::PRAZO_DA_BASE + premium::ConsultaPaga::FOLGA)
    end

    it 'religando tudo (lista vazia), os 22 datasets voltam aos cards' do
      desligar_na_fonte!([])

      expect(catalogo.premium.sum { |card| card.consultas.size }).to eq(22)
      expect(catalogo.buscar('certidoes_empresa').openai_schema(slug: 'x', usar_quando: nil)[:parameters][:properties]['consulta']['enum'])
        .to eq(%w[divida_uniao trabalhista fgts cnj cadin])
    end

    it 'o card grátis de uma consulta só não ganha a frase das Premium' do
      schema = catalogo.buscar('cnpj').openai_schema(slug: 'pronta_cnpj', usar_quando: nil)

      expect(schema[:description]).not_to include('Responde só a:')
    end
  end

  # #2946: os processos levaram 36 s e as empresas na região 81 s no teste direto; o prazo da base (20 s) cortava as duas.
  it 'os processos e as empresas na região têm o prazo das lentas (120 s); as outras da base seguem com 20 s' do
    prazos = catalogo.premium.flat_map(&:consultas).to_h { |consulta| [consulta.dataset.nome, consulta.dataset.prazo] }

    expect(prazos.slice('processes', 'companies_statistics').values).to eq([120, 120])
    expect(prazos.fetch('kyc')).to eq(premium::Dataset::PRAZO_DA_BASE)
    expect(prazos.fetch('ondemand_cnj_negative_certificate_company')).to eq(premium::Dataset::PRAZO_SOB_DEMANDA)
    expect(premium.prazo_maximo).to eq(122)
    expect(catalogo.buscar('raio_x_empresa').consulta('processos').prazo_total).to eq(122)
  end

  it 'todo preço do catálogo fecha em centavos inteiros (o embargo do IBAMA, R$ 0,225, sobe para R$ 0,23)' do
    todas_as_consultas_premium.each do |consulta|
      centavos = consulta.dataset.preco * 100
      expect(centavos).to eq(centavos.to_i), consulta.nome
    end
  end

  it 'o preço de todo dataset é o custo × 1,5, arredondado para cima ao centavo' do
    todas_as_consultas_premium.each do |consulta|
      expect(consulta.dataset.preco_confere?).to be(true), consulta.nome
    end
  end

  it 'sem limite diário só vale para card Premium: fonte grátis sem limite nem nasce' do
    atributos = { chave: 'exemplo', slug: 'pronta_exemplo', nome: 'EXEMPLO', descricao: 'EXEMPLO', termos: 'EXEMPLO',
                  consultas: described_class.buscar('cep').consultas, limite_diario: nil }

    expect { Autonomia::FerramentasProntas::Fonte.new(**atributos) }.to raise_error(ArgumentError)
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
    rotas = todas_as_consultas_premium.map { |consulta| consulta.dataset.rota }.uniq
    expect(Autonomia::Prospecting::Research::BigDataCorpClient::ROUTES).to include(*rotas)
  end

  it 'nenhum card tem parâmetro de contato, endereço ou parente de pessoa física (recusa por desenho do schema)' do
    parametros = todas_as_consultas_premium.flat_map(&:parametros).map(&:nome).uniq
    expect(parametros).to contain_exactly('cnpj', 'cpf', 'placa', 'cep', 'numero', 'codigo_car', 'cidade', 'uf', 'rua', 'bairro')
    # O endereço (QI 70) só para achar o CEP, no risco do endereço e nas empresas da região: nunca para achar quem mora lá.
    # Ele é local (não vai à BigDataCorp) e não existe no telefone nem no e-mail, que só aceitam o CNPJ.
    pelo_endereco = todas_as_consultas_premium.select { |consulta| consulta.parametro('rua') }
    expect(pelo_endereco.map(&:nome)).to contain_exactly('area_de_risco', 'vistoria', 'empresas_na_regiao')
    expect(todas_as_consultas_premium.flat_map(&:parametros).select { |parametro| %w[cidade uf rua bairro].include?(parametro.nome) })
      .to all(be_local)

    contato = catalogo.buscar('contato_empresa')
    expect(%w[telefone email].map { |nome| contato.consulta(nome).parametros.map(&:nome) }).to eq([['cnpj'], ['cnpj']])
    expect(consultas_do_card('conferir_pessoa').map { |consulta| consulta.dataset.nome })
      .to contain_exactly('ondemand_rf_status_person', 'basic_data', 'class_organization')
  end

  it 'fora: score de crédito, contato de pessoa física, parentes, antecedentes, política, apostas, SUS e TSE' do
    datasets = todas_as_consultas_premium.map { |consulta| consulta.dataset.nome }
    proibidos = %w[financial_risk credit_score collections phones emails addresses related_people family_relationships
                   criminal_records political_involvement electoral_donors online_gambling sus_data tse_data]
    expect(datasets & proibidos).to be_empty
  end

  it 'o schema do card de várias consultas pede a consulta pelo nome e aceita só os parâmetros do card' do
    schema = catalogo.buscar('conferir_pessoa').openai_schema(slug: 'pronta_conferir_pessoa', usar_quando: nil)
    propriedades = schema[:parameters][:properties]
    expect(propriedades['consulta']['enum']).to eq(%w[nome_e_nascimento conselho])
    expect(propriedades.keys).to contain_exactly('consulta', 'cpf')
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

require 'rails_helper'

# #2858 (F4): as fontes de seguros do lote 2 — produtos das seguradoras (Open Insurance Brasil) e corretor na SUSEP —
# pelo caminho real (a `Execucao` da ferramenta pronta de um agente), com o WebMock no lugar da fonte e respostas reais
# encurtadas (`spec/fixtures/ferramentas_prontas/`).
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:uso) { Autonomia::FerramentasProntas::Uso.sole }
  let(:produtos) { Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras }
  let(:corretor) { Autonomia::FerramentasProntas::Fontes::CorretorSusep }
  let(:hosts) do
    # As seguradoras têm host dinâmico (do diretório): não entram no helper.
    { 'api.opin.allianz.com.br' => '93.184.216.61', 'auth.tokiomarine.com.br' => '93.184.216.62',
      'api.hdiglobal.opinb3.com.br' => '93.184.216.63' }
  end

  before do
    resolver_hosts_das_prontas
    hosts.each { |host, ip| allow(Resolv).to receive(:getaddresses).with(host).and_return([ip]) }
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, 'agente_ferramentas_prontas_lote2')
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00')) { example.run } }

  def fixture(nome)
    Rails.root.join('spec/fixtures/ferramentas_prontas', nome).read
  end

  def nao_consegui?(saida)
    saida['situacao'] == 'nao_consegui_consultar' && !saida.key?('dados')
  end

  describe 'a flag do lote 2' do
    it 'desligada, as fontes de seguros nao entram e nao consultam' do
      ferramenta = incluir_pronta('corretor_susep', conta: account, agente: agent)
      account.disable_features!('agente_ferramentas_prontas_lote2')

      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_nome', 'nome' => 'CORRETORA'))).to be(true)
      expect { incluir_pronta('produtos_seguradoras', conta: account, agente: agent) }
        .to raise_error(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
      expect(a_request(:get, /susep/)).not_to have_been_made
    end
  end

  describe 'Produtos das seguradoras (Open Insurance Brasil, so garantia e transporte)' do
    # A fonte saiu da vitrine (decisao do Rodrigo, 11/11): o agente que ja a tem continua consultando.
    let(:ferramenta) { pronta_ja_incluida('produtos_seguradoras', conta: account, agente: agent) }
    let(:diretorio) { 'https://data.directory.opinbrasil.com.br/participants' }
    let(:allianz) { 'https://api.opin.allianz.com.br/open-insurance/products-services/v2/transport' }
    let(:tokio_publica) { 'https://auth.tokiomarine.com.br/open-insurance/products-services/v2/public-guarantee' }
    let(:tokio_privada) { 'https://auth.tokiomarine.com.br/open-insurance/products-services/v1/private-guarantee' }
    let(:hdi_global) { 'https://api.hdiglobal.opinb3.com.br/open-insurance/products-services/v3/transport' }

    def transporte(seguradora, busca: nil)
      executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => seguradora, 'ramo' => 'transporte', 'busca' => busca)
    end

    def allianz_com(**por_produto)
      corpo = JSON.parse(fixture('opin_allianz_transporte.json'))
      corpo['data']['brand']['companies'].first['products'].each do |produto|
        por_produto.fetch(produto['name'].tr('-', '_').to_sym, {}).each { |campo, valor| produto[campo.to_s] = valor }
      end
      corpo
    end

    before { fonte_responde(diretorio, fixture('opin_diretorio.json'), tipo: 'application/json') }

    it 'so tres ramos: garantia publica, garantia privada e transporte' do
      expect(produtos::RAMOS.keys).to eq(%w[garantia_publica garantia_privada transporte])
      expect(executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'Allianz', 'ramo' => 'riscos_ciberneticos'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'ramo')
    end

    it 'o cache de antes (27 ramos, sem o filtro) nao e lido: a chave muda com a versao' do
      produtos::FONTE.consultas.each do |consulta|
        expect(consulta.chave_do_cache({})).to include('versao_do_cache' => 2)
      end
      expect(produtos::Diretorio::CHAVE).to include(':v2:')
    end

    it 'diz ao agente que e entre as que publicam no Open Insurance, e quem nao publica' do
      expect(produtos::FONTE.descricao).to include('entre as seguradoras que publicam no Open Insurance', 'Junto', 'Pottencial', 'Akad',
                                                   'Fairfax')
      expect(produtos::FONTE.descricao).not_to include('as seguradoras que fazem')
    end

    it 'lista as seguradoras ativas pelo diretorio; com busca, os ramos de cada uma (sem auto e sem servidor de teste)' do
      todas = executar_pronta(ferramenta, 'consulta' => 'seguradoras')
      tokio = executar_pronta(ferramenta, 'consulta' => 'seguradoras', 'busca' => 'tokio marine')

      expect(todas['dados']).to eq('total' => 4, 'seguradoras' => ['ALLIANZ SEGUROS', 'HDI Global', 'HDI Seguros', 'Tokio Marine Seguradora S/A'])
      expect(tokio['dados']['seguradoras']).to eq([{ 'nome' => 'Tokio Marine Seguradora S/A',
                                                     'ramos' => ['Seguro garantia (setor privado)', 'Seguro garantia (setor público)',
                                                                 'Transportes'] }])
      expect(tokio.to_json).not_to include('https://', 'Inativa')
    end

    it 'servidor de teste no diretorio de producao: a marca so com ele some, e a versao de teste perde para a de producao' do
      fonte_responde(tokio_privada, { data: { brand: { name: 'Tokio Marine', companies: [] } }, meta: { totalRecords: 0 } })

      porto = executar_pronta(ferramenta, 'consulta' => 'seguradoras', 'busca' => 'porto')
      privada = executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'tokio', 'ramo' => 'garantia_privada')

      expect(porto['situacao']).to eq('nao_encontrado')
      expect(transporte('btg')['situacao']).to eq('nao_encontrado')
      expect(privada['dados']['seguradoras'].pluck('seguradora')).to eq(['Tokio Marine Seguradora S/A'])
      expect(a_request(:get, tokio_privada)).to have_been_made.once
      expect(a_request(:get, /sandbox|openinsurance-dev|api-hml/)).not_to have_been_made
    end

    it 'resume os produtos da seguradora no endereco da maior versao do diretorio: nome, coberturas e condicoes' do
      fonte_responde(allianz, fixture('opin_allianz_transporte.json'))

      saida = transporte('allianz')

      seguradora = saida['dados']['seguradoras'].sole
      expect(saida['dados']['ramo']).to eq('Transportes')
      expect(seguradora).to include('seguradora' => 'ALLIANZ SEGUROS', 'total' => 3)
      expect(seguradora['produtos'].pluck('nome')).to eq(['RCTR-C', 'RCF-DC', 'Transporte Nacional'])
      expect(seguradora['produtos'].first['condicoes'])
        .to eq('https://www.allianz.com.br/seguros/veja-outros-seguros/transportes/responsabilidade-civil-transporte/documentos.html')
      expect(saida.to_json).not_to include('maxLMG', '00000000000000', 'RESPONSABILIDADE_CIVIL_DO_TRANSPORTADOR')
      expect(a_request(:get, allianz).with(headers: { 'Cache-Control' => 'no-cache' })).to have_been_made.once
    end

    it 'busca pelo nome do produto e tambem pelas coberturas ("carga" acha o RCF-DC da Allianz)' do
      fonte_responde(allianz, fixture('opin_allianz_transporte.json'))

      carga = transporte('allianz', busca: 'carga')

      expect(carga['dados']['seguradoras'].sole['produtos'].pluck('nome')).to eq(['RCF-DC'])
      expect(transporte('allianz', busca: 'rctr')['dados']['seguradoras'].sole['produtos'].pluck('nome')).to eq(['RCTR-C'])
      expect(transporte('allianz', busca: 'fianca')['situacao']).to eq('nao_encontrado')
    end

    it 'link de exemplo, link sem pontuacao e link do proprio Open Insurance: o produto fica, sem as condicoes' do
      corpo = allianz_com(
        RCTR_C: { termsAndConditions: { definition: 'https://www.seguradora.com.br/produto/tradicional/pdf/condicoes_gerais.pdf' } },
        RCF_DC: { termsAndConditions: [{ definition: 'HTTPSWWWBRADESCOSEGUROSCOMBRCONDICOESGERAIS' },
                                       { definition: 'https://exemplo.com.br/condicoes.pdf' }, { definition: 'https://example.com/cg' }] },
        'Transporte Nacional': { termsAndConditions: { definition: 'https://openinsurance.com.br/aaa' } }
      )
      fonte_responde(allianz, corpo)

      produtos_da_allianz = transporte('allianz')['dados']['seguradoras'].sole['produtos']

      expect(produtos_da_allianz.pluck('nome')).to eq(['RCTR-C', 'RCF-DC', 'Transporte Nacional'])
      expect(produtos_da_allianz.pluck('condicoes')).to eq([nil, nil, nil])
    end

    it 'resposta de sandbox num host de producao ("Produto de Seguro", cobertura "string"): nenhum produto' do
      fonte_responde(allianz, fixture('opin_sandbox_produto_de_exemplo.json'))

      saida = transporte('allianz')

      expect(saida['dados']['seguradoras']).to eq([{ 'seguradora' => 'ALLIANZ SEGUROS', 'total' => 0, 'produtos' => [] }])
      expect(saida.to_json).not_to include('Produto de Seguro', '"string"', 'seguradora.com.br')
    end

    it 'cobertura "string" sai do produto de verdade' do
      coberturas = [{ coverage: 'X', coverageDescription: 'string' }, { coverage: 'Y', coverageDescription: 'Colisao' }]
      fonte_responde(allianz, allianz_com(RCTR_C: { coverages: coberturas }))

      expect(transporte('allianz', busca: 'rctr')['dados']['seguradoras'].sole['produtos'].sole['coberturas']).to eq(['Colisao'])
    end

    it 'guarda o diretorio: a segunda seguradora nao baixa o diretorio de novo' do
      cache_em_memoria
      fonte_responde(allianz, fixture('opin_allianz_transporte.json'))
      fonte_responde(hdi_global, fixture('opin_allianz_transporte.json'))

      transporte('allianz')
      transporte('hdi global')

      expect(a_request(:get, diretorio)).to have_been_made.once
      expect(a_request(:get, hdi_global)).to have_been_made.once
    end

    it 'duas seguradoras com o nome: a que nao responde no prazo sai em nao_responderam, e a outra responde' do
      fonte_responde(allianz, fixture('opin_allianz_transporte.json'))
      fonte_lenta(hdi_global)

      saida = transporte('seguros')

      expect(saida['dados']['seguradoras'].pluck('seguradora')).to eq(['ALLIANZ SEGUROS'])
      expect(saida['dados']['nao_responderam']).to eq(['HDI Global'])
    end

    it 'diretorio fora do prazo: "nao consegui", sem chamar seguradora nenhuma' do
      fonte_lenta(diretorio)

      expect(nao_consegui?(transporte('allianz'))).to be(true)
      expect(uso.motivos).to eq('openinsurance.tempo_esgotado' => 1)
      expect(a_request(:get, allianz)).not_to have_been_made
    end

    it 'a seguradora fora do ar (500): "nao consegui", com o motivo e o nome dela no log' do
      fonte_fora(allianz)
      allow(Rails.logger).to receive(:warn).and_call_original

      expect(nao_consegui?(transporte('allianz'))).to be(true)
      expect(uso.motivos).to eq('openinsurance.seguradora_nao_respondeu' => 1)
      expect(Rails.logger).to have_received(:warn).with(include('marca=ALLIANZ SEGUROS motivo=erro_da_fonte'))
    end

    it 'formato mudado: diretorio que nao e lista e seguradora fora do formato viram "nao consegui"' do
      fonte_responde(allianz, { data: [] })

      expect(nao_consegui?(transporte('allianz'))).to be(true)

      fonte_responde(diretorio, { participants: [] })
      expect(nao_consegui?(transporte('allianz'))).to be(true)
      expect(uso.motivos).to eq('openinsurance.seguradora_nao_respondeu' => 1, 'openinsurance.resposta_invalida' => 1)
    end

    it 'endereco do diretorio fora do HTTPS, com porta ou com marcador: o ramo nem aparece' do
      participantes = JSON.parse(fixture('opin_diretorio.json'))
      recursos = participantes.find { |item| item['OrganisationName'].start_with?('ALLIANZ') }['AuthorisationServers'].first['ApiResources']
      fora = ['http://api.opin.allianz.com.br/transport', 'https://api.opin.allianz.com.br:8443/transport']
      recursos.select { |item| item['ApiFamilyType'] == 'products-services_transport' }.each_with_index do |item, indice|
        item['ApiDiscoveryEndpoints'] = [{ 'ApiEndpoint' => fora[indice] }]
      end
      fonte_responde(diretorio, participantes)

      saida = transporte('allianz')

      expect(saida['dados']).to include('seguradoras' => [], 'ramos_publicados' => ['Seguro garantia (setor público)'])
      expect(a_request(:get, /allianz/)).not_to have_been_made
    end

    it 'entrada fora do formato: ramo fora da lista ou seguradora de uma letra, sem consultar' do
      expect(executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'Allianz', 'ramo' => 'auto'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'ramo')
      expect(executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'A', 'ramo' => 'transporte'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'seguradora')
      expect(a_request(:get, diretorio)).not_to have_been_made
    end

    it 'lista vazia: seguradora que nao esta no diretorio, a que nao publica o ramo e a que publica zero produtos' do
      fonte_responde(tokio_publica, { data: { brand: { name: 'Tokio Marine', companies: [] } }, meta: { totalRecords: 0 } })

      sem_ramo = executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'allianz', 'ramo' => 'garantia_privada')
      vazia = executar_pronta(ferramenta, 'consulta' => 'produtos', 'seguradora' => 'tokio', 'ramo' => 'garantia_publica')

      expect(transporte('seguradora que nao existe')['situacao']).to eq('nao_encontrado')
      expect(sem_ramo['dados']).to include('seguradoras' => [], 'encontradas' => ['ALLIANZ SEGUROS'],
                                           'ramos_publicados' => ['Seguro garantia (setor público)', 'Transportes'])
      expect(vazia['dados']['seguradoras']).to eq([{ 'seguradora' => 'Tokio Marine Seguradora S/A', 'total' => 0, 'produtos' => [] }])
    end
  end

  describe 'Corretor na SUSEP (consulta publica, sem documentacao)' do
    let(:ferramenta) { incluir_pronta('corretor_susep', conta: account, agente: agent) }
    let(:base) { 'https://www2.susep.gov.br/safe/corretoresapig/dadospublicos/pesquisar' }
    let(:por_cnpj) { "#{base}?tipoPessoa=PJ&cpfCnpj=11222333000181" }
    let(:por_nome) { "#{base}?tipoPessoa=PJ&nome=CORRETORA%20EXEMPLO" }
    let(:por_cpf) { "#{base}?tipoPessoa=PF&cpfCnpj=11144477735" }

    def com_registro(**campos)
      corpo = JSON.parse(fixture('susep_por_cnpj.json'))
      corpo['retorno']['registros'].first.merge!(campos.stringify_keys)
      corpo
    end

    it 'trava o formato esperado: so nome, situacao, registro e ramos; nunca o corretorId nem o documento' do
      fonte_responde(por_cnpj, fixture('susep_por_cnpj.json'), tipo: 'application/json')

      saida = executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '11.222.333/0001-81')

      expect(saida['dados']).to eq('total' => 1, 'corretores' => [{
                                     'nome' => 'CORRETORA EXEMPLO DE SEGUROS LTDA', 'situacao' => 'Ativo', 'registro_susep' => '202000001',
                                     'ramos' => ['Seguros de Danos', 'Seguros de Pessoas', 'Planos de Capitalização']
                                   }])
      expect(saida.to_json).not_to include('900001', '11222333000181', 'corretorId', 'cpfCnpj')
    end

    it 'pelo nome, com o tipo de pessoa; o suspenso vem sem ramos' do
      fonte_responde("#{base}?tipoPessoa=PJ&nome=Corretora%20exemplo", fixture('susep_por_nome.json'))

      saida = executar_pronta(ferramenta, 'consulta' => 'por_nome', 'nome' => ' Corretora   exemplo ', 'tipo_pessoa' => 'PJ')

      expect(saida['dados']['total']).to eq(2)
      expect(saida['dados']['corretores'].pluck('situacao', 'ramos').last).to eq(['Suspenso', []])
    end

    it 'pelo CPF: confere o meio do CPF mascarado; mascarado de outro CPF e formato mudado' do
      fonte_responde(por_cpf, com_registro(cpfCnpj: '***444777**'))
      expect(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '111.444.777-35')['dados']['total']).to eq(1)

      Rails.cache.clear
      fonte_responde(por_cpf, com_registro(cpfCnpj: '***999888**'))
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '111.444.777-35'))).to be(true)
    end

    it 'filtro ignorado pela SUSEP (voltou outro nome): "nao consegui" e ALERTA no log, sem quebrar' do
      fonte_responde("#{base}?nome=SILVA", fixture('susep_por_nome.json'))
      allow(Rails.logger).to receive(:warn).and_call_original

      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_nome', 'nome' => 'SILVA'))).to be(true)
      expect(uso.motivos).to eq('susep.formato_mudou' => 1)
      expect(Rails.logger).to have_received(:warn).with(include('ALERTA corretor_susep', 'campo=nome'))
    end

    it 'formato mudado: sem retorno, registros que nao sao lista ou registro sem situacao' do
      [{ registros: [] }, { retorno: { totalRegistros: 1, registros: {} } }, com_registro(situacao: nil)].each do |corpo|
        Rails.cache.clear
        fonte_responde(por_cnpj, corpo)
        expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '11222333000181'))).to be(true)
      end
      expect(uso.motivos).to eq('susep.formato_mudou' => 3)
    end

    it 'prazo e erro: a SUSEP lenta ou fora (500) e "nao consegui"' do
      fonte_lenta(por_cnpj)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '11222333000181'))).to be(true)

      fonte_fora(por_nome)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'por_nome', 'nome' => 'CORRETORA EXEMPLO', 'tipo_pessoa' => 'pj'))).to be(true)
      expect(uso.motivos).to eq('susep.tempo_esgotado' => 1, 'susep.erro_da_fonte' => 1)
    end

    it 'entrada fora do formato: CPF com digito errado, CNPJ invalido e nome curto, sem consultar' do
      expect(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '111.444.777-36'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'documento')
      expect(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '11.222.333/0001-82'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'documento')
      expect(executar_pronta(ferramenta, 'consulta' => 'por_nome', 'nome' => 'ab')).to include('situacao' => 'pedido_invalido', 'campo' => 'nome')
      expect(a_request(:get, /susep/)).not_to have_been_made
    end

    it 'lista vazia: nenhum corretor com o documento e "nao encontrado"' do
      fonte_responde(por_cnpj, { retorno: { paginaAtual: 1, tamanhoPagina: 25, totalRegistros: 0, registros: [] }, mensagem: nil })

      expect(executar_pronta(ferramenta, 'consulta' => 'por_documento', 'documento' => '11222333000181')['situacao']).to eq('nao_encontrado')
    end
  end
end

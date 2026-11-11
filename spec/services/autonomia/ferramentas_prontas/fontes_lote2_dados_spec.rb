require 'rails_helper'

# #2858 (F4, dados): código de mercadoria (NCM), compras do governo (PNCP), estações do tempo (INMET) e quanto choveu
# (Open-Meteo), pelo caminho real (a `Execucao` da pronta de um agente), com o WebMock no lugar da fonte. Cada uma: a
# resposta boa, o prazo, o erro do provedor, a entrada fora do formato e a lista vazia.
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:uso) { Autonomia::FerramentasProntas::Uso.sole }

  before do
    resolver_hosts_das_prontas
    account.enable_features!(Autonomia::FerramentasProntas::FLAG, 'agente_ferramentas_prontas_lote2')
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00')) { example.run } }

  def nao_consegui?(saida)
    saida['situacao'] == 'nao_consegui_consultar' && !saida.key?('dados')
  end

  def nenhum_pedido_saiu?
    WebMock::RequestRegistry.instance.requested_signatures.hash.empty?
  end

  it 'as quatro levam a flag do lote 2 e, sem ela, nao entram' do
    chaves = %w[ncm compras_governo estacoes chuva]
    expect(chaves.map { |chave| Autonomia::FerramentasProntas::Catalogo.buscar(chave).flag }.uniq).to eq(['agente_ferramentas_prontas_lote2'])

    account.disable_features!('agente_ferramentas_prontas_lote2')
    chaves.each do |chave|
      expect { incluir_pronta(chave, conta: account, agente: agent) }
        .to raise_error(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
    end
  end

  describe 'Codigo de mercadoria (NCM, BrasilAPI)' do
    let(:ferramenta) { incluir_pronta('ncm', conta: account, agente: agent) }
    let(:busca) { 'https://brasilapi.com.br/api/ncm/v1?search=parafuso%20de%20a%C3%A7o' }
    let(:vigente) do
      { codigo: '7318.15.00', descricao: '-- Outros parafusos e pinos ou pernos', data_inicio: '2022-04-01', data_fim: '9999-12-31',
        tipo_ato: 'Res Camex', numero_ato: '000272', ano_ato: '2021' }
    end
    let(:vencido) { vigente.merge(codigo: '7318.15.90', data_fim: '2021-12-31') }
    # A posição (73.18): a única chamada do código de 8 dígitos. Aqui sem os níveis de cima, para a descrição ficar a do
    # próprio nível.
    let(:posicao) { 'https://brasilapi.com.br/api/ncm/v1?search=7318' }

    it '"Qual a NCM de parafuso de aco?": os codigos vigentes, com o texto da busca codificado na URL' do
      fonte_responde(busca, [vigente, vencido])

      dados = executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => '  parafuso   de aço ')['dados']

      expect(dados).to eq('busca' => 'parafuso de aço', 'total' => 1,
                          'itens' => [{ 'codigo' => '7318.15.00', 'descricao' => 'Outros parafusos e pinos ou pernos',
                                        'vigente_desde' => '2022-04-01',
                                        'observacao' => Autonomia::FerramentasProntas::Fontes::Ncm::CONFIRA }])
    end

    # A BrasilAPI devolve na ordem do código: a palavra no meio da descrição de outro capítulo (34.03, lubrificantes
    # "antiaderentes de porcas e parafusos") vinha antes do 73.18. A ordem por relevância vem antes do corte.
    it '"Qual a NCM de parafuso?": primeiro a descricao que comeca pela palavra, e o corte vem depois da ordem' do
      item = ->(codigo, descricao) { vigente.merge(codigo: codigo, descricao: descricao) }
      outros = (1..20).map { |n| item.call(format('34.%02d', n), "Preparações antiaderentes de porcas e parafusos #{n}") }
      fonte_responde('https://brasilapi.com.br/api/ncm/v1?search=parafuso',
                     outros + [item.call('73.18', 'Parafusos, pinos ou pernos')])

      dados = executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => 'parafuso')['dados']

      expect(dados).to include('total' => 21, 'mostrando' => 20)
      expect(dados['itens'].first(3).pluck('codigo')).to eq(%w[73.18 34.01 34.02])
      expect(dados['itens'].pluck('codigo')).not_to include('34.20')
    end

    # Só o código de 8 dígitos vai na nota: no mesmo grupo de relevância, ele vem antes da posição (4) e do capítulo (2).
    it 'no mesmo grupo, o codigo de 8 digitos antes do de 4 e do de 2' do
      item = ->(codigo, descricao) { vigente.merge(codigo: codigo, descricao: descricao) }
      fonte_responde('https://brasilapi.com.br/api/ncm/v1?search=parafuso',
                     [item.call('73', 'Parafusos de ferro'), item.call('73.18', 'Parafusos, pinos ou pernos'),
                      item.call('7318.14.00', '-- Parafusos autoperfurantes'), item.call('34.03', 'Preparações de porcas e parafusos'),
                      item.call('7318.15.00', '-- Outros parafusos e pinos')])

      dados = executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => 'parafuso')['dados']

      expect(dados['itens'].pluck('codigo')).to eq(%w[7318.14.00 73.18 73 7318.15.00 34.03])
      # Nenhum grupo abre sozinho (revisão do #2917): quem escolhe é o modelo.
      expect(a_request(:get, posicao)).not_to have_been_made
    end

    # Regra QI 70 (decisão de 11/11/2026): com códigos que diferem por um detalhe que o cliente não disse, o agente
    # responde o do caso comum e cita o outro, em vez de travar a conversa perguntando.
    it 'as descricoes dizem ao modelo que so o codigo de 8 digitos vai na nota e que responda o caso comum' do
      textos = Autonomia::FerramentasProntas::Catalogo.buscar('ncm').consultas.map(&:descricao).join(' ')

      expect(textos).to include('8 dígitos', 'nota', 'capítulo', 'posição', Autonomia::FerramentasProntas::Fontes::Ncm::CASO_COMUM)
      expect(textos).not_to include('antes de dizer o código')
    end

    it '"O que e a NCM 7318.15.00?": a descricao oficial, pelo codigo sem os pontos e sem os tracos do nivel' do
      fonte_responde(posicao, [vigente])

      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '7318.15.00')['dados'])
        .to eq('codigo' => '7318.15.00', 'descricao' => 'Outros parafusos e pinos ou pernos', 'vigente_desde' => '2022-04-01')
    end

    # Varredura P11: a tabela do Siscomex traz HTML na descrição ("600 g/m<sup>2</sup>", "<i>badminton</i>").
    it 'a descricao vai sem as tags HTML, com o texto delas e as entidades decodificadas' do
      fonte_responde(posicao, [vigente.merge(descricao: 'De peso igual ou superior a 600 g/m<sup>2</sup>, de <i>badminton</i> &amp; outros')])

      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '7318.15.00')['dados']['descricao'])
        .to eq('De peso igual ou superior a 600 g/m2, de badminton & outros')
    end

    it 'codigo que nao existe (fora da posicao dele) e busca sem resultado: "nao encontrado"' do
      fonte_responde('https://brasilapi.com.br/api/ncm/v1?search=9999', [])
      fonte_responde('https://brasilapi.com.br/api/ncm/v1?search=xyzqwk', [])

      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '99999999')['situacao']).to eq('nao_encontrado')
      expect(executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => 'xyzqwk')['situacao']).to eq('nao_encontrado')
    end

    it 'sem reserva: a BrasilAPI lenta ou fora e "nao consegui", com o motivo no contador' do
      fonte_lenta(posicao)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '73181500'))).to be(true)

      fonte_fora(busca, status: 502)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => 'parafuso de aço'))).to be(true)
      expect(uso.motivos).to eq('brasilapi.tempo_esgotado' => 1, 'brasilapi.erro_da_fonte' => 1)
    end

    it 'busca curta demais e codigo com letra ou tamanho errado: pedido invalido, sem chamar a fonte' do
      expect(executar_pronta(ferramenta, 'consulta' => 'buscar', 'busca' => 'pa')).to include('situacao' => 'pedido_invalido', 'campo' => 'busca')
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '7318A500')['campo']).to eq('codigo')
      expect(executar_pronta(ferramenta, 'consulta' => 'codigo', 'codigo' => '731815')['campo']).to eq('codigo')
      expect(nenhum_pedido_saiu?).to be(true)
    end
  end

  describe 'Compras do governo (PNCP)' do
    let(:ferramenta) { incluir_pronta('compras_governo', conta: account, agente: agent) }
    let(:pncp) do
      'https://pncp.gov.br/api/consulta/v1/contratacoes/publicacao?dataInicial=20261101&dataFinal=20261105' \
        '&codigoModalidadeContratacao=6&codigoMunicipioIbge=3170206&pagina=1&tamanhoPagina=50'
    end
    let(:compra) do
      { orgaoEntidade: { cnpj: '25769548000121', razaoSocial: 'DEPARTAMENTO MUNICIPAL DE AGUA E ESGOTO' },
        unidadeOrgao: { nomeUnidade: 'DMAE UBERLANDIA', codigoIbge: '3170206' }, anoCompra: 2026, sequencialCompra: 235,
        objetoCompra: 'Registro de preços para aquisição de materiais hidráulicos', valorTotalEstimado: 11_420.2,
        dataPublicacaoPncp: '2026-11-03T11:34:41', situacaoCompraNome: 'Divulgada no PNCP', usuarioNome: 'Fulana Servidora',
        linkSistemaOrigem: 'https://outro.exemplo.test/compra' }
    end
    let(:limpeza) { compra.merge(sequencialCompra: 236, objetoCompra: 'Contratação de serviço de limpeza predial') }

    it '"Licitacoes em Uberlandia esta semana?": orgao, objeto, valor, data e o link do PNCP, sem quem cadastrou' do
      fonte_responde(pncp, { data: [compra, limpeza], totalRegistros: 2, totalPaginas: 1 })

      saida = executar_pronta(ferramenta, 'cidade' => 'uberlandia', 'uf' => 'MG', 'de' => '01/11/2026', 'ate' => '2026-11-05')
      dados = saida['dados']

      expect(dados).to include('cidade' => 'Uberlândia', 'uf' => 'MG', 'de' => '2026-11-01', 'ate' => '2026-11-05',
                               'modalidade' => 'Pregão eletrônico', 'total' => 2)
      expect(dados['compras'].first).to eq(
        'orgao' => 'DEPARTAMENTO MUNICIPAL DE AGUA E ESGOTO', 'unidade' => 'DMAE UBERLANDIA',
        'objeto' => 'Registro de preços para aquisição de materiais hidráulicos', 'valor_estimado' => 11_420.2,
        'publicada_em' => '2026-11-03', 'situacao' => 'Divulgada no PNCP', 'link' => 'https://pncp.gov.br/app/editais/25769548000121/2026/235'
      )
      expect(saida.to_json).not_to include('Fulana', 'outro.exemplo')
    end

    # Item real do PNCP (Uberlândia, 05/11/2026; em
    # app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/dados-reais/compras_governo.json): o valor
    # sigiloso ou não informado vem como 0. Zero não é o valor da compra, então o campo sai e o agente não diz "R$ 0".
    it 'valor estimado sigiloso (0 no PNCP): o campo nao vai ao agente' do
      sigilosa = { orgaoEntidade: { cnpj: '15126437000305', razaoSocial: 'EMPRESA BRASILEIRA DE SERVICOS HOSPITALARES - EBSERH' },
                   unidadeOrgao: { nomeUnidade: 'HOSPITAL DAS CLIN DA UNIV FED DE UBERLÂNDIA' }, anoCompra: 2026, sequencialCompra: 4546,
                   objetoCompra: 'PRODUTOS PARA SAÚDE - UROLOGIA - DIAGNÓSTICO POR IMAGEM E GINECOLOGIA - REEDIÇÃO',
                   valorTotalEstimado: 0, dataPublicacaoPncp: '2026-11-05T09:12:00', situacaoCompraNome: 'Divulgada no PNCP' }
      fonte_responde(pncp, { data: [sigilosa], totalRegistros: 1 })

      dados = executar_pronta(ferramenta, 'cidade' => 'uberlandia', 'uf' => 'MG', 'de' => '2026-11-01', 'ate' => '2026-11-05')['dados']

      expect(dados['compras'].first).not_to have_key('valor_estimado')
      expect(dados['compras'].first).to include('orgao' => 'EMPRESA BRASILEIRA DE SERVICOS HOSPITALARES - EBSERH')
    end

    it 'pelo codigo IBGE, com modalidade e busca local no objeto; acima de uma pagina, avisa que olhou so as primeiras' do
      fonte_responde(pncp.sub('codigoModalidadeContratacao=6', 'codigoModalidadeContratacao=8'),
                     { data: [compra, limpeza], totalRegistros: 120, totalPaginas: 3 })

      dados = executar_pronta(ferramenta, 'codigo_ibge' => '3170206', 'modalidade' => 'dispensa', 'busca' => 'LIMPEZA',
                                          'de' => '2026-11-01', 'ate' => '2026-11-05')['dados']

      expect(dados['compras'].pluck('link')).to eq(['https://pncp.gov.br/app/editais/25769548000121/2026/236'])
      expect(dados).to include('modalidade' => 'Dispensa', 'total' => 1, 'total_no_periodo' => 120)
      expect(dados['observacao']).to include('120 compras').and include('encurte o período')
    end

    it 'sem periodo: os ultimos 7 dias ate hoje' do
      padrao = pncp.sub('dataInicial=20261101&dataFinal=20261105', 'dataInicial=20261104&dataFinal=20261110')
      fonte_responde(padrao, { data: [compra], totalRegistros: 1 })

      expect(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'mg')['dados']).to include('de' => '2026-11-04', 'ate' => '2026-11-10')
    end

    it 'sem compra no periodo (lista vazia, ou 204 sem corpo) e busca que nao acha nada: "nao encontrado"' do
      fonte_responde(pncp, { data: [], totalRegistros: 0, empty: true })
      argumentos = { 'codigo_ibge' => '3170206', 'de' => '2026-11-01', 'ate' => '2026-11-05' }
      expect(executar_pronta(ferramenta, argumentos)['situacao']).to eq('nao_encontrado')

      Rails.cache.clear
      stub_request(:get, pncp).to_return(status: 204, body: '', headers: { 'Content-Type' => 'application/json' })
      expect(executar_pronta(ferramenta, argumentos)['situacao']).to eq('nao_encontrado')

      Rails.cache.clear
      fonte_responde(pncp, { data: [compra], totalRegistros: 1 })
      expect(executar_pronta(ferramenta, argumentos.merge('busca' => 'merenda'))['situacao']).to eq('nao_encontrado')
    end

    it 'prazo e erro do PNCP: "nao consegui"' do
      argumentos = { 'codigo_ibge' => '3170206', 'de' => '2026-11-01', 'ate' => '2026-11-05' }
      fonte_lenta(pncp)
      # O período inteiro estourou o prazo: o último dia (#2906, F32/F33), lento também.
      fonte_lenta(pncp.sub('dataInicial=20261101', 'dataInicial=20261105'))
      expect(nao_consegui?(executar_pronta(ferramenta, argumentos))).to be(true)

      fonte_fora(pncp, status: 503)
      expect(nao_consegui?(executar_pronta(ferramenta, argumentos))).to be(true)
      expect(uso.motivos).to eq('pncp.tempo_esgotado' => 1, 'pncp.erro_da_fonte' => 1)
    end

    it 'so a cidade, unica no Brasil: a UF sai dela (regra QI 70)' do
      fonte_responde(pncp, { data: [compra], totalRegistros: 1 })

      expect(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'de' => '2026-11-01', 'ate' => '2026-11-05')['situacao']).to eq('encontrado')
    end

    it 'cidade que nao existe no estado, homonima sem uf, codigo de 6 digitos ou periodo longo: pedido invalido, sem chamar a fonte' do
      expect(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'SP')).to include('campo' => 'uf', 'candidatos' => ['MG'])
      expect(executar_pronta(ferramenta, 'cidade' => 'Bom Jesus')).to include('campo' => 'uf', 'candidatos' => %w[PB PI RN RS SC])
      expect(executar_pronta(ferramenta, 'codigo_ibge' => '317020')['campo']).to eq('codigo_ibge')
      expect(executar_pronta(ferramenta, 'codigo_ibge' => '3170206', 'de' => '2026-09-01', 'ate' => '2026-11-05')['campo']).to eq('ate')
      expect(executar_pronta(ferramenta, 'codigo_ibge' => '3170206', 'modalidade' => 'tomada_de_precos')['campo']).to eq('modalidade')
      expect(nenhum_pedido_saiu?).to be(true)
    end
  end

  describe 'Estacoes do tempo (INMET)' do
    let(:ferramenta) { incluir_pronta('estacoes', conta: account, agente: agent) }
    let(:inmet) { 'https://apitempo.inmet.gov.br/estacoes/T' }
    let(:estacoes) do
      [{ DC_NOME: 'UBERLANDIA', CD_ESTACAO: 'A507', SG_ESTADO: 'MG', CD_SITUACAO: 'Operante', VL_LATITUDE: '-18.91694444',
         VL_LONGITUDE: '-48.25555555', TP_ESTACAO: 'Automatica' },
       { DC_NOME: 'UBERABA', CD_ESTACAO: 'A568', SG_ESTADO: 'MG', CD_SITUACAO: 'Pane', VL_LATITUDE: '-19.71',
         VL_LONGITUDE: '-47.96' },
       { DC_NOME: 'BRASILIA', CD_ESTACAO: 'A001', SG_ESTADO: 'DF', CD_SITUACAO: 'Operante', VL_LATITUDE: '-15.78944444',
         VL_LONGITUDE: '-47.92583332' },
       { DC_NOME: 'SAO PAULO - MIRANTE', CD_ESTACAO: 'A701', SG_ESTADO: 'SP', CD_SITUACAO: 'Operante', VL_LATITUDE: '-23.49629',
         VL_LONGITUDE: '-46.62' },
       { DC_NOME: 'SEM COORDENADA', CD_ESTACAO: 'A999', SG_ESTADO: 'SP', VL_LATITUDE: nil }]
    end

    it '"Qual a estacao do INMET mais perto de Uberlandia?": as 3 mais perto, com situacao e distancia' do
      fonte_responde(inmet, estacoes)

      dados = executar_pronta(ferramenta, 'cidade' => 'uberlândia', 'uf' => 'MG')['dados']

      expect(dados['perto_de']).to eq('Uberlândia (MG)')
      expect(dados['estacoes'].pluck('codigo')).to eq(%w[A507 A568 A001])
      expect(dados['estacoes'].first).to include('nome' => 'UBERLANDIA', 'uf' => 'MG', 'situacao' => 'Operante', 'distancia_km' => 2.0)
      expect(dados['estacoes'].second).to include('situacao' => 'Pane')
    end

    it 'a lista vai ao cache uma vez so: outra cidade e uma coordenada nao baixam de novo, e o ponto nunca sai daqui' do
      cache_em_memoria
      pedido = fonte_responde(inmet, estacoes)

      executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'MG')
      dados = executar_pronta(ferramenta, 'latitude' => -23.5505, 'longitude' => -46.6333)['dados']

      expect(dados).to include('perto_de' => 'a localização informada')
      expect(dados['estacoes'].first).to include('codigo' => 'A701')
      expect(pedido).to have_been_requested.once
      expect(a_request(:get, /latitude|-23\.55|Uberl/i)).not_to have_been_made
    end

    it 'longe de qualquer estacao (fora do Brasil) e lista sem estacao valida: "nao encontrado" ou "nao consegui"' do
      fonte_responde(inmet, estacoes)
      expect(executar_pronta(ferramenta, 'latitude' => 48.85, 'longitude' => 2.35)['situacao']).to eq('nao_encontrado')

      Rails.cache.clear
      fonte_responde(inmet, [{ DC_NOME: 'SEM COORDENADA' }])
      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'MG'))).to be(true)
    end

    it 'prazo e erro do INMET: "nao consegui"' do
      fonte_lenta(inmet)
      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'MG'))).to be(true)

      fonte_fora(inmet)
      expect(nao_consegui?(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'MG'))).to be(true)
      expect(uso.motivos).to eq('inmet.tempo_esgotado' => 1, 'inmet.erro_da_fonte' => 1)
    end

    it 'so a cidade, unica no Brasil: a UF sai dela (regra QI 70)' do
      fonte_responde(inmet, estacoes)

      expect(executar_pronta(ferramenta, 'cidade' => 'Uberlândia')['dados']['perto_de']).to eq('Uberlândia (MG)')
    end

    it 'sem lugar, cidade homonima sem uf, cidade de outro estado ou so a latitude: pedido invalido, sem chamar a fonte' do
      expect(executar_pronta(ferramenta, {})['campo']).to eq('cidade')
      expect(executar_pronta(ferramenta, 'cidade' => 'Bom Jesus')).to include('campo' => 'uf', 'candidatos' => %w[PB PI RN RS SC])
      expect(executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'RJ')).to include('campo' => 'uf', 'candidatos' => ['MG'])
      expect(executar_pronta(ferramenta, 'latitude' => -18.9)['campo']).to eq('longitude')
      expect(executar_pronta(ferramenta, 'latitude' => 'perto', 'longitude' => -48.2)['campo']).to eq('latitude')
      expect(nenhum_pedido_saiu?).to be(true)
    end
  end

  describe 'Quanto choveu (Open-Meteo)' do
    let(:ferramenta) { incluir_pronta('chuva', conta: account, agente: agent) }
    let(:base) { 'https://archive-api.open-meteo.com/v1/archive' }
    let(:uberlandia) { "#{base}?latitude=-18.91&longitude=-48.27&start_date=2026-11-08&end_date=2026-11-10&daily=precipitation_sum&timezone=auto" }
    let(:resposta) do
      { latitude: -18.87, longitude: -48.27, timezone: 'America/Sao_Paulo',
        daily_units: { time: 'iso8601', precipitation_sum: 'mm' },
        daily: { time: %w[2026-11-08 2026-11-09 2026-11-10], precipitation_sum: [32.7, 9.4, 4.5] } }
    end

    it '"Quanto choveu em Uberlandia de 08 a hoje?": o total e cada dia, estimativa, atribuicao e hoje parcial' do
      fonte_responde(uberlandia, resposta)

      dados = executar_pronta(ferramenta, 'cidade' => 'Uberlandia', 'uf' => 'MG', 'de' => '08/11/2026', 'ate' => '2026-11-10')['dados']

      expect(dados).to include('local' => 'Uberlândia (MG)', 'de' => '2026-11-08', 'ate' => '2026-11-10', 'total_mm' => 46.6,
                               'fonte_dos_dados' => 'Dados do tempo por Open-Meteo.com (CC BY 4.0)')
      expect(dados['dias']).to eq([{ 'data' => '2026-11-08', 'mm' => 32.7 }, { 'data' => '2026-11-09', 'mm' => 9.4 },
                                   { 'data' => '2026-11-10', 'mm' => 4.5 }])
      expect(dados['observacao']).to include('não a medição de um pluviômetro').and include('parcial')
    end

    it 'sem data e pela localizacao: o dia de ontem, com a coordenada arredondada a ~1 km' do
      ontem = "#{base}?latitude=-23.55&longitude=-46.63&start_date=2026-11-09&end_date=2026-11-09&daily=precipitation_sum&timezone=auto"
      fonte_responde(ontem, resposta.merge(daily: { time: ['2026-11-09'], precipitation_sum: [0.0] }))

      dados = executar_pronta(ferramenta, 'latitude' => -23.550_52, 'longitude' => -46.633_31)['dados']

      expect(dados).to include('local' => 'a localização informada', 'total_mm' => 0.0, 'de' => '2026-11-09')
      expect(dados['observacao']).not_to include('parcial')
    end

    it 'dia que a fonte ainda nao tem (valor nulo em todos): "nao encontrado"' do
      fonte_responde(uberlandia, resposta.merge(daily: { time: %w[2026-11-08 2026-11-09 2026-11-10], precipitation_sum: [nil, nil, nil] }))

      saida = executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'uf' => 'MG', 'de' => '2026-11-08', 'ate' => '2026-11-10')

      expect(saida['situacao']).to eq('nao_encontrado')
    end

    it 'prazo, erro e resposta torta do Open-Meteo: "nao consegui"' do
      argumentos = { 'cidade' => 'Uberlândia', 'uf' => 'MG', 'de' => '2026-11-08', 'ate' => '2026-11-10' }
      fonte_lenta(uberlandia)
      expect(nao_consegui?(executar_pronta(ferramenta, argumentos))).to be(true)

      fonte_fora(uberlandia, status: 400)
      expect(nao_consegui?(executar_pronta(ferramenta, argumentos))).to be(true)

      fonte_responde(uberlandia, resposta.merge(daily: { time: %w[2026-11-08], precipitation_sum: [1.0, 2.0] }))
      expect(nao_consegui?(executar_pronta(ferramenta, argumentos))).to be(true)
      expect(uso.motivos).to eq('openmeteo.tempo_esgotado' => 1, 'openmeteo.pedido_recusado' => 1, 'openmeteo.resposta_invalida' => 1)
    end

    it 'futuro, periodo longo ou ao contrario, data torta e lugar que falta: pedido invalido, sem chamar a fonte' do
      lugar = { 'cidade' => 'Uberlândia', 'uf' => 'MG' }
      expect(executar_pronta(ferramenta, lugar.merge('de' => '2026-11-11'))['campo']).to eq('de')
      expect(executar_pronta(ferramenta, lugar.merge('de' => '2026-10-01', 'ate' => '2026-10-20'))['campo']).to eq('ate')
      expect(executar_pronta(ferramenta, lugar.merge('de' => '2026-11-05', 'ate' => '2026-11-01'))['campo']).to eq('ate')
      expect(executar_pronta(ferramenta, lugar.merge('de' => 'semana passada'))['campo']).to eq('de')
      expect(executar_pronta(ferramenta, 'longitude' => -48.2)['campo']).to eq('latitude')
      expect(nenhum_pedido_saiu?).to be(true)
    end

    it 'cidade homonima sem uf traz as UFs candidatas; cidade que nao existe pede a cidade' do
      expect(executar_pronta(ferramenta, 'cidade' => 'Bom Jesus')).to include('campo' => 'uf', 'candidatos' => %w[PB PI RN RS SC])
      expect(executar_pronta(ferramenta, 'cidade' => 'Cidade Que Nao Existe')['campo']).to eq('cidade')
      expect(nenhum_pedido_saiu?).to be(true)
    end

    it '"Vai chover em Uberlandia?": so a cidade basta, a UF sai dela' do
      fonte_responde(uberlandia, resposta)

      dados = executar_pronta(ferramenta, 'cidade' => 'Uberlândia', 'de' => '2026-11-08', 'ate' => '2026-11-10')['dados']

      expect(dados).to include('local' => 'Uberlândia (MG)', 'total_mm' => 46.6)
    end
  end
end

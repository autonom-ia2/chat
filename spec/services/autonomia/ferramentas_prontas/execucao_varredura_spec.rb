require 'rails_helper'

# #2906 — os defeitos de servidor que a varredura real das prontas achou (318 casos, 11/11/2026). Cada exemplo cita o
# achado (F = fonte, P = tela) e o caso do corpus que o mostrou.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
    ligar_consultas(account)
    account.enable_features!(Autonomia::FerramentasProntas::Fontes::Ncm::FLAG)
  end

  def pronta(fonte)
    incluir_pronta(fonte, conta: account, agente: agent)
  end

  # Como no turno real: o modelo manda os argumentos, a fonte os normaliza, a execução consulta.
  def turno(fonte, argumentos)
    enviados = Autonomia::FerramentasProntas::Catalogo.buscar(fonte).normalizar_argumentos(argumentos)
    executar_pronta(pronta(fonte), enviados)
  end

  describe 'CEP' do
    let(:brasil_api) { 'https://brasilapi.com.br/api/cep/v2/99999999' }
    let(:via_cep) { 'https://viacep.com.br/ws/99999999/json/' }

    it 'F01 (cep/endereco/07): endereco que a BrasilAPI tirou do open-cep nao vale; o ViaCEP sem o CEP: nao encontrado' do
      fonte_responde(brasil_api, { cep: '99999999', state: 'PR', city: 'Sarandi', street: 'Rua X', service: 'open-cep' })
      fonte_responde(via_cep, { erro: 'true' })

      expect(turno('cep', 'consulta' => 'endereco', 'cep' => '99999-999')['situacao']).to eq('nao_encontrado')
    end

    it 'F01: do open-cep, vale o que o ViaCEP disser' do
      fonte_responde(brasil_api, { cep: '99999999', state: 'PR', city: 'Sarandi', service: 'open-cep' })
      fonte_responde(via_cep, { cep: '99999-999', logradouro: 'Rua Oficial', bairro: 'Centro', localidade: 'Maringá', uf: 'PR' })

      expect(turno('cep', 'consulta' => 'endereco', 'cep' => '99999999')['dados']).to include('cidade' => 'Maringá')
    end

    it 'F02 (cep/por_endereco/09,10): "Av. Brasil" vai ao ViaCEP sem o ponto' do
      url = 'https://viacep.com.br/ws/SP/Sao%20Paulo/Av%20Brasil/json/'
      fonte_responde(url, [{ cep: '01430-001', logradouro: 'Avenida Brasil', bairro: 'Jardim América', ibge: '3550308' }])

      saida = turno('cep', 'consulta' => 'por_endereco', 'logradouro' => 'Av. Brasil', 'cidade' => 'São Paulo')

      expect(saida['dados']['ceps'].pluck('cep')).to eq(['01430-001'])
    end

    it 'F03 (cep/por_endereco/02): rua nao achada orienta a mandar o nome completo, sem abreviar' do
      fonte_responde('https://viacep.com.br/ws/SP/Sao%20Paulo/av%20paulista/json/', [])

      saida = turno('cep', 'consulta' => 'por_endereco', 'logradouro' => 'av paulista', 'cidade' => 'São Paulo')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('nome completo', 'sem abreviar')
    end
  end

  describe 'F04-F07: o marcador "(fora do formato)" nunca vai a fonte' do
    it 'cep/por_endereco/11: a rua curta demais e pedido invalido, sem chamar o ViaCEP' do
      saida = turno('cep', 'consulta' => 'por_endereco', 'logradouro' => 'ab', 'cidade' => 'São Paulo')

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'logradouro')
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    end

    it 'ncm/buscar/08: a busca curta demais e pedido invalido, sem chamar a BrasilAPI' do
      saida = turno('ncm', 'consulta' => 'buscar', 'busca' => 'ab')

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'busca')
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
    end

    it 'todo parametro de texto livre recusa o marcador' do
      consultas = Autonomia::FerramentasProntas::Catalogo.todas.flat_map(&:consultas)
      textos = consultas.flat_map(&:parametros).reject(&:opcoes).uniq
      aceitos = textos.select { |parametro| parametro.normalizar(Autonomia::FerramentasProntas::Fonte::FORA_DO_FORMATO) }

      expect(aceitos.map(&:nome)).to be_empty
    end
  end

  describe 'CNPJ' do
    let(:url) { 'https://brasilapi.com.br/api/cnpj/v1/33000167000101' }

    it 'F09 (cnpj/empresa/01): o CNAE volta com os 7 digitos (o zero da frente)' do
      fonte_responde(url, { razao_social: 'PETROLEO BRASILEIRO S A PETROBRAS', cnae_fiscal: 600_001,
                            cnae_fiscal_descricao: 'Extração de petróleo e gás natural' })

      dados = turno('cnpj', 'cnpj' => '33.000.167/0001-01')['dados']

      expect(dados['atividade_principal']).to include('codigo' => '0600001')
    end

    it 'F10 (cnpj/empresa/05): o CNPJ com texto em volta vale, como o CEP e o CPF' do
      expect(Autonomia::FerramentasProntas::Parametro.cnpj('cnpj 33.000.167/0001-01 ')).to eq('33000167000101')
      expect(Autonomia::FerramentasProntas::Parametro.cnpj('12.ABC.345/01DE-35')).to eq('12ABC34501DE35')
    end
  end

  describe 'FIPE' do
    let(:marcas) { 'https://brasilapi.com.br/api/fipe/marcas/v1/carros' }
    let(:vw) { 'https://parallelum.com.br/fipe/api/v2/cars/brands/59' }
    let(:lista_vw) do
      [{ code: '1', name: 'Gol 1.0 Mi Total Flex 8V 4p' }, { code: '2', name: 'Gol 1.6 Power' }, { code: '3', name: 'Golf 2.0' },
       { code: '9', name: 'Gol GTi 2.0' }, { code: '2380', name: 'Fusca 1300' }]
    end

    def preco_de(modelo, valor, ano: 2020)
      { price: valor, brand: 'VW - VolksWagen', model: modelo, modelYear: ano, fuel: 'Gasolina', codeFipe: '005340-6',
        referenceMonth: 'novembro de 2026 ' }
    end

    def preco(argumentos)
      turno('fipe', { 'consulta' => 'preco', 'tipo' => 'carros', 'marca' => 'Volkswagen' }.merge(argumentos))
    end

    before do
      fonte_responde(marcas, [{ nome: 'VW - VolksWagen', valor: '59' }, { nome: 'Fiat', valor: '21' }])
      fonte_responde("#{vw}/models", lista_vw)
      fonte_responde("#{vw}/years", [{ code: '2020-1', name: '2020 Gasolina' }, { code: '2020-5', name: '2020 Flex' },
                                     { code: '2019-1', name: '2019 Gasolina' }])
      fonte_responde("#{vw}/years/2020-1/models", [{ code: '2', name: 'Gol 1.6 Power' }])
      fonte_responde("#{vw}/years/2020-5/models", [{ code: '1', name: 'Gol 1.0 Mi Total Flex 8V 4p' }])
    end

    it 'F12 (fipe/preco/01): "Gol 2020" usa o ano para estreitar e devolve a faixa de 2 versoes, sem exigir escolha' do
      fonte_responde("#{vw}/models/1/years", [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde("#{vw}/models/1/years/2020-5", preco_de('Gol 1.0 Mi Total Flex 8V 4p', 'R$ 41.000,00'))
      fonte_responde("#{vw}/models/2/years", [{ code: '2020-1', name: '2020 Gasolina' }])
      fonte_responde("#{vw}/models/2/years/2020-1", preco_de('Gol 1.6 Power', 'R$ 52.500,50'))

      saida = preco('modelo' => 'Gol', 'ano' => 2020)

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']['precos'].pluck('valor')).to eq([41_000.0, 52_500.5])
      expect(saida['dados']['observacao']).to include('versões', 'versão')
      expect(a_request(:get, "#{vw}/models/9/years")).not_to have_been_made
    end

    it 'F12: com uma versao so no ano, vai direto ao preco dela' do
      fonte_responde("#{vw}/years/2020-1/models", [])
      fonte_responde("#{vw}/models/1/years", [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde("#{vw}/models/1/years/2020-5", preco_de('Gol 1.0 Mi Total Flex 8V 4p', 'R$ 41.000,00'))

      saida = preco('modelo' => 'Gol', 'ano' => 2020)

      expect(saida['dados']['precos'].sole).to include('modelo' => 'Gol 1.0 Mi Total Flex 8V 4p')
      expect(saida['dados']).not_to have_key('observacao')
    end

    it 'F12: sem o ano e com varias versoes, pergunta o ano (que estreita), com as versoes em candidatos' do
      saida = preco('modelo' => 'Gol')

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'ano')
      expect(saida['candidatos'].pluck('codigo')).to contain_exactly('1', '2', '9')
      expect(saida['orientacao']).to include('ano-modelo')
    end

    it 'F13 (fipe/preco/07): "Gol 1850" diz que o ano nao existe, sem consultar preco' do
      saida = preco('modelo' => 'Gol', 'ano' => 1850)

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'ano')
      expect(saida['orientacao']).to include('1850', 'não existe')
    end

    it 'F13 (fipe/preco/10): "Fusca 1975" de um modelo so mostra os anos que existem' do
      fonte_responde("#{vw}/models/2380/years", [{ code: '1980-1', name: '1980 Gasolina' }, { code: '1983-1', name: '1983 Gasolina' }])

      saida = preco('modelo' => 'Fusca', 'ano' => 1975)

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']['anos_disponiveis']).to eq(['1980 Gasolina', '1983 Gasolina'])
      expect(saida['dados']['observacao']).to include('1975')
    end

    it 'F11 (fipe/preco/04): "Fiat 500" e o nome, mesmo com o codigo 500 na lista de outro modelo' do
      fiat = 'https://parallelum.com.br/fipe/api/v2/cars/brands/21'
      fonte_responde("#{fiat}/models", [{ code: '500', name: 'Tempra 2.0' }, { code: '5613', name: '500 Cult 1.4 Flex 8V' }])
      fonte_responde("#{fiat}/models/5613/years", [{ code: '2015-1', name: '2015 Gasolina' }])
      fonte_responde("#{fiat}/models/5613/years/2015-1", preco_de('500 Cult 1.4 Flex 8V', 'R$ 40.000,00', ano: 2015))

      saida = preco('marca' => 'Fiat', 'modelo' => '500', 'ano' => 2015)

      expect(saida['dados']['precos'].sole).to include('modelo' => '500 Cult 1.4 Flex 8V')
      expect(a_request(:get, "#{fiat}/models/500/years")).not_to have_been_made
    end

    it 'P09 (fipe/preco/12): o valor vai em numero, a moeda em unidades e o mes em ISO, para a tela formatar' do
      fonte_responde("#{vw}/models/2/years", [{ code: '2020-1', name: '2020 Gasolina' }])
      fonte_responde("#{vw}/models/2/years/2020-1", preco_de('Gol 1.6 Power', 'R$ 56.043,00'))

      dados = preco('modelo' => '2', 'ano' => 2020)['dados']

      expect(dados['precos'].sole).to include('valor' => 56_043.0, 'mes_de_referencia' => '2026-11')
      expect(dados['unidades']).to eq('valor' => 'R$')
    end
  end

  describe 'DDD' do
    it 'F14 (ddd/12,13): aceita o 0 de longa distancia na frente, com ou sem a operadora' do
      ddd = Autonomia::FerramentasProntas::Fontes::Ddd
      expect(['034', '(034) 3333-4444', '0 34 3333 4444', '0 15 34 99999 0000'].map { |texto| ddd.ddd_do_telefone(texto) })
        .to eq(%w[34 34 34 34])
    end
  end

  describe 'Localizacao' do
    it 'F15 (localizacao/04): a coordenada com virgula decimal vale' do
      expect(Autonomia::FerramentasProntas::Fontes::Localizacao.coordenada('-23,55', 90)).to eq(-23.55)
    end

    it 'F16 (localizacao/03): 0,0 (o mar) e nao encontrado, nao "nao consegui"' do
      fonte_responde('https://photon.komoot.io/reverse?lat=0.0&lon=0.0&lang=default&limit=1', { features: [] })

      expect(turno('localizacao', 'latitude' => 0, 'longitude' => 0)['situacao']).to eq('nao_encontrado')
    end
  end

  describe 'Bancos' do
    let(:lista) { 'https://brasilapi.com.br/api/banks/v1' }
    let(:bancos) do
      [{ name: 'BCO BRADESCO FINANC. S.A.', code: 394, fullName: 'Banco Bradesco Financiamentos S.A.' },
       { name: 'BCO BRADESCO S.A.', code: 237, fullName: 'Banco Bradesco S.A.' },
       { name: 'SANTANDER CTVM S.A.', code: 352, fullName: 'SANTANDER CORRETORA DE CAMBIO E VALORES MOBILIARIOS S.A.' },
       { name: 'BCO SANTANDER (BRASIL) S.A.', code: 33, fullName: 'Banco Santander (Brasil) S.A.' }]
    end

    it 'F18 (bancos/por_nome/03,09): o banco principal (o nome de registro mais curto) vem primeiro' do
      fonte_responde(lista, bancos)

      expect(turno('bancos', 'consulta' => 'por_nome', 'nome' => 'Bradesco')['dados']['bancos'].first['codigo']).to eq('237')
      expect(turno('bancos', 'consulta' => 'por_nome', 'nome' => 'Santander')['dados']['bancos'].first['codigo']).to eq('033')
    end

    it 'F20 (bancos/banco/09): "0341" e o 341' do
      expect(Autonomia::FerramentasProntas::Fontes::Bancos.codigo('0341')).to eq('341')
      expect(Autonomia::FerramentasProntas::Fontes::Bancos.codigo('0000')).to be_nil
    end

    it 'F19 (bancos/por_nome/07): a descricao do nome pede o nome por extenso, nao a sigla' do
      expect(Autonomia::FerramentasProntas::Fontes::Bancos::NOME.descricao).to include('por extenso')
    end
  end

  describe 'Termo tecnico: doencas e procedimentos' do
    it 'F27 (doencas/busca/06): "dor de cabeca" nao achada orienta o termo tecnico' do
      saida = turno('doencas', 'consulta' => 'busca', 'busca' => 'dor de cabeça')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('termo técnico', 'cefaleia')
    end

    it 'F26 (doencas/codigo/08): U07.1 nao esta na tabela do DATASUS; a orientacao diz que o codigo novo pode faltar' do
      saida = turno('doencas', 'consulta' => 'codigo', 'codigo' => 'U07.1')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('DATASUS')
    end

    it 'F30 (procedimentos/busca/03): sem achar, orienta o termo tecnico (radiografia)' do
      saida = turno('procedimentos', 'consulta' => 'busca', 'busca' => 'chapa do pulmao')

      expect(saida['orientacao']).to include('termo técnico', 'radiografia')
    end

    it 'F17/F24: a descricao da busca ja orienta o termo tecnico (doencas, procedimentos, NCM)' do
      expect(Autonomia::FerramentasProntas::Fontes::Doencas::BUSCA.descricao).to include('termo técnico')
      expect(Autonomia::FerramentasProntas::Fontes::Procedimentos::BUSCA.descricao).to include('termo técnico')
      expect(Autonomia::FerramentasProntas::Fontes::Ncm::BUSCA.descricao).to include('telefones celulares')
    end
  end

  describe 'Hospitais' do
    let(:base) { 'https://apidadosabertos.saude.gov.br/cnes/estabelecimentos?codigo_municipio=350950&status=1&limit=20' }

    def unidade(nome, cep: '13015001')
      { nome_fantasia: nome, codigo_cnes: '1234567', codigo_tipo_unidade: 5, codigo_cep_estabelecimento: cep,
        descricao_natureza_juridica_estabelecimento: '1000 ADMINISTRACAO PUBLICA' }
    end

    it 'F22 (hospitais/12): a busca pelo nome olha alem da primeira pagina' do
      fonte_responde("#{base}&offset=0", { estabelecimentos: Array.new(20) { |i| unidade("CLINICA #{i}") } })
      fonte_responde("#{base}&offset=20", { estabelecimentos: [unidade('SANTA CASA DE CAMPINAS')] })

      saida = turno('hospitais', 'cidade' => 'Campinas', 'uf' => 'sp', 'busca' => 'santa casa')

      expect(saida['dados']['estabelecimentos'].pluck('nome')).to eq(['SANTA CASA DE CAMPINAS'])
    end

    it 'F21 (hospitais/01): no teto de paginas, diz que e amostra (o total nao e o da cidade)' do
      paginas = Autonomia::FerramentasProntas::Fontes::Hospitais::MAX_PAGINAS
      paginas.times do |pagina|
        fonte_responde("#{base}&offset=#{pagina * 20}", { estabelecimentos: Array.new(20) { |i| unidade("U #{pagina}-#{i}") } })
      end

      dados = turno('hospitais', 'cidade' => 'Campinas', 'uf' => 'sp')['dados']

      expect(dados['observacao']).to include('amostra')
      expect(dados['observacao']).not_to include('estabelecimentos', 'olhei', 'li ')
    end

    it 'F22 (hospitais/12, real): o nome nao achado orienta mandar o tipo junto (a cidade grande so e lida em parte)' do
      fonte_responde("#{base}&offset=0", { estabelecimentos: [unidade('CLINICA A')] })

      saida = turno('hospitais', 'cidade' => 'Campinas', 'uf' => 'sp', 'busca' => 'santa casa')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('tipo', 'santa casa é hospital')
    end

    it 'P14: o CEP do estabelecimento vem com o traco' do
      fonte_responde("#{base}&offset=0", { estabelecimentos: [unidade('HOSPITAL A')] })

      expect(turno('hospitais', 'cidade' => 'Campinas', 'uf' => 'sp')['dados']['estabelecimentos'].sole).to include('cep' => '13015-001')
    end
  end

  describe 'Cidade e estado' do
    it 'F38 (estacoes, chuva): a uf pelo nome do estado ("são paulo") vale' do
      uf = Autonomia::FerramentasProntas::Municipios.parametro_uf
      expect([uf.normalizar('são paulo'), uf.normalizar('SP'), uf.normalizar('Narnia')]).to eq(['sp', 'sp', nil])
    end

    it 'F38 (cidades/cidades/03): a uf da consulta de cidades tambem vale pelo nome do estado' do
      expect(Autonomia::FerramentasProntas::Fontes::Cidades::UF.normalizar('são paulo')).to eq('sp')
    end

    it 'F39 (hospitais/06): "Rio Branco" sem uf e a capital; sem capital entre as homonimas, pergunta' do
      municipios = Autonomia::FerramentasProntas::Municipios

      expect(municipios.buscar(nil, 'Rio Branco')).to have_attributes(uf: 'AC')
      expect(municipios.buscar(nil, 'Bom Jesus')).to be_nil
      expect(municipios.falta(nil, 'Bom Jesus')).to have_attributes(campo: 'uf')
    end
  end

  describe 'Compras do governo' do
    let(:pncp) do
      lambda do |de|
        "https://pncp.gov.br/api/consulta/v1/contratacoes/publicacao?dataInicial=#{de}&dataFinal=20261105" \
          '&codigoModalidadeContratacao=6&codigoMunicipioIbge=3170206&pagina=1&tamanhoPagina=50'
      end
    end
    let(:compra) do
      { orgaoEntidade: { cnpj: '25769548000121', razaoSocial: 'DMAE' }, unidadeOrgao: { nomeUnidade: 'DMAE' }, anoCompra: 2026,
        sequencialCompra: 235, objetoCompra: 'Materiais hidráulicos', valorTotalEstimado: 11_420.2,
        dataPublicacaoPncp: '2026-11-05T11:34:41' }
    end

    def compras
      turno('compras_governo', 'cidade' => 'Uberlândia', 'de' => '2026-11-01', 'ate' => '2026-11-05')
    end

    it 'F32/F33 (compras/03,05,06): a chamada cabe no prazo final da consulta, com a abertura da conexao dentro dele' do
      consulta = Autonomia::FerramentasProntas::Fontes::ComprasGoverno::FONTE.consulta('compras')

      expect(consulta.prazo_por_fonte + Autonomia::FerramentasProntas::ClienteHttp::ABERTURA).to be <= consulta.prazo_total
    end

    it 'F32/F33: o periodo inteiro estoura o prazo; vem o ultimo dia, como parcial e sem cache, em vez de "nao consegui"' do
      stub_request(:get, pncp.call('20261101')).to_timeout
      fonte_responde(pncp.call('20261105'), { data: [compra], totalRegistros: 1 })

      saida = compras

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']).to include('de' => '2026-11-05', 'ate' => '2026-11-05')
      expect(saida['dados']['observacao']).to include('último dia')
      expect(compras['dados']['observacao']).to include('último dia')
      expect(a_request(:get, pncp.call('20261101'))).to have_been_made.twice
    end

    it 'P07 (compras/02): a observacao e neutra, sem a voz do agente' do
      texto = Autonomia::FerramentasProntas::Fontes::ComprasGoverno::SO_A_PRIMEIRA_PAGINA
      expect(texto).not_to include('olhei')
    end
  end

  describe 'Banco Central' do
    it 'P10: a Selic vai com a unidade em codigo (a tela traduz); o IPCA com o mes em ISO' do
      banco = Autonomia::FerramentasProntas::Fontes::BancoCentral
      expect(banco.selic(15.0)).to include('unidade' => 'percentual_ao_ano')
      expect(banco::UNIDADES_DO_FOCUS['selic']).to eq('percentual_ao_ano')

      fonte_responde('https://api.bcb.gov.br/dados/serie/bcdata.sgs.433/dados/ultimos/1?formato=json', [{ data: '01/10/2026', valor: '0.09' }])
      fonte_responde('https://api.bcb.gov.br/dados/serie/bcdata.sgs.13522/dados/ultimos/1?formato=json', [{ data: '01/10/2026', valor: '4.68' }])

      expect(turno('banco_central', 'consulta' => 'ipca')['dados']).to include('mes_de_referencia' => '2026-10')
    end
  end

  it 'P06 (produtos_seguradoras): a observacao nao cita o nome do campo' do
    texto = Autonomia::FerramentasProntas::Fontes::ProdutosSeguradoras::OpenInsurance::SEM_O_RAMO
    expect(texto).not_to include('ramos_publicados')
  end
end

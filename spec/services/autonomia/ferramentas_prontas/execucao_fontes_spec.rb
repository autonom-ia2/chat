require 'rails_helper'

# #2858 (F0): cada adaptador da fase — CEP, CNPJ e FIPE — com a resposta boa, o prazo (fonte que não responde), a
# reserva e o erro. Pelo caminho real: a `Execucao` da ferramenta pronta de um agente, com o WebMock no lugar da fonte.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end

  before do
    resolver_hosts_das_prontas
    ligar_prontas(account)
  end

  describe 'CEP (ViaCEP, reserva AwesomeAPI, ultima reserva BrasilAPI)' do
    let(:ferramenta) { incluir_pronta('cep', conta: account, agente: agent) }
    let(:viacep) { 'https://viacep.com.br/ws/01001000/json/' }
    let(:awesomeapi) { 'https://cep.awesomeapi.com.br/json/01001000' }
    let(:brasilapi) { 'https://brasilapi.com.br/api/cep/v2/01001000' }
    let(:do_viacep) do
      { cep: '01001-000', logradouro: 'Praça da Sé', complemento: 'lado ímpar', bairro: 'Sé', localidade: 'São Paulo',
        uf: 'SP', ibge: '3550308', ddd: '11' }
    end
    # A resposta real da AwesomeAPI (11/11/2026): latitude, longitude e DDD não vão ao agente.
    let(:da_awesomeapi) do
      { cep: '01001000', address_type: 'Praça', address_name: 'da Sé', address: 'Praça da Sé', state: 'SP', district: 'Sé',
        lat: '-23.5500806', lng: '-46.6340827', city: 'São Paulo', city_ibge: '3550308', ddd: '11' }
    end
    let(:da_brasilapi) do
      { cep: '01001000', state: 'SP', city: 'São Paulo', neighborhood: 'Sé', street: 'Praça da Sé', service: 'open-cep',
        location: { type: 'Point', coordinates: { longitude: '-46.63', latitude: '-23.55' } } }
    end
    let(:esperado) { { 'cep' => '01001-000', 'logradouro' => 'Praça da Sé', 'bairro' => 'Sé', 'cidade' => 'São Paulo', 'uf' => 'SP' } }

    it 'responde pela principal (ViaCEP), com o endereço enxuto e o CEP como o cliente escreveu' do
      fonte_responde(viacep, do_viacep)
      reservas = [fonte_responde(awesomeapi, da_awesomeapi), fonte_responde(brasilapi, da_brasilapi)]

      saida = executar_pronta(ferramenta, 'cep' => '01001-000')

      expect(saida).to include('situacao' => 'encontrado', 'dados' => esperado, 'consulta' => 'endereco')
      reservas.each { |reserva| expect(reserva).not_to have_been_requested }
    end

    it 'cai na AwesomeAPI quando a principal estoura o prazo, sem a coordenada nem o DDD' do
      fonte_lenta(viacep)
      fonte_responde(awesomeapi, da_awesomeapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')).to include('situacao' => 'encontrado', 'dados' => esperado)
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(consultas: 1, pela_reserva: 1,
                                                                         motivos: { 'viacep.tempo_esgotado' => 1 })
    end

    it 'com o ViaCEP no teto, a AwesomeAPI responde e o ViaCEP nao e chamado' do
      allow(Autonomia::FerramentasProntas::TetoDoProvedor).to receive(:reservar!).and_call_original
      allow(Autonomia::FerramentasProntas::TetoDoProvedor).to receive(:reservar!).with('viacep.com.br', conta: anything, saida: nil).and_return(false)
      fonte_responde(awesomeapi, da_awesomeapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')['dados']).to eq(esperado)
      expect(a_request(:get, viacep)).not_to have_been_made
      expect(a_request(:get, brasilapi)).not_to have_been_made
      expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('viacep.teto_do_provedor' => 1)
    end

    it 'CEP que nao existe (99999-999): o ViaCEP e a AwesomeAPI dizem que nao tem, e a BrasilAPI (open-cep) nem e chamada' do
      fonte_responde('https://viacep.com.br/ws/99999999/json/', { erro: 'true' })
      fonte_responde('https://cep.awesomeapi.com.br/json/99999999', { code: 'not_found', message: 'O CEP 99999999 nao foi encontrado' },
                     status: 404)
      inventado = fonte_responde('https://brasilapi.com.br/api/cep/v2/99999999',
                                 { cep: '99999999', state: 'PR', city: 'Sarandi', street: 'Avenida das Torres', service: 'open-cep' })

      saida = executar_pronta(ferramenta, 'cep' => '99999-999')

      expect(saida['situacao']).to eq('nao_encontrado')
      expect(saida['orientacao']).to include('Não invente')
      expect(inventado).not_to have_been_requested
      expect(Autonomia::FerramentasProntas::Uso.sole.nao_encontradas).to eq(1)
    end

    it 'com o ViaCEP e a AwesomeAPI fora do ar (5xx), a BrasilAPI responde, inclusive pelo open-cep' do
      fonte_fora(viacep, status: 502)
      fonte_fora(awesomeapi, status: 503)
      fonte_responde(brasilapi, da_brasilapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')).to include('situacao' => 'encontrado', 'dados' => esperado)
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(
        pela_reserva: 1, motivos: { 'viacep.erro_da_fonte' => 1, 'awesomeapi.erro_da_fonte' => 1 }
      )
    end

    # O endereço que o open-cep pode inventar não fica 30 dias valendo para todas as contas: a próxima consulta do
    # mesmo CEP vai de novo à ViaCEP. A resposta da principal continua no cache.
    it 'a resposta da BrasilAPI nao vai ao cache, e a do ViaCEP vai' do
      loja = cache_em_memoria
      allow(loja).to receive(:write).and_call_original
      fonte_fora(viacep, status: 502)
      fonte_fora(awesomeapi, status: 503)
      fonte_responde(brasilapi, da_brasilapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')['dados']).to eq(esperado)
      expect(loja).not_to have_received(:write).with(start_with('autonomia:prontas:'), anything, anything)

      fonte_responde(viacep, do_viacep)
      2.times { expect(executar_pronta(ferramenta, 'cep' => '01001000')['dados']).to eq(esperado) }
      # Uma vez fora (502), uma respondendo; a terceira consulta sai do cache que o ViaCEP gravou.
      expect(a_request(:get, viacep)).to have_been_made.twice
    end

    it 'com uma dizendo que nao tem e a outra fora, nao afirma que o CEP nao existe e nao vai a BrasilAPI' do
      fonte_responde(viacep, { erro: 'true' })
      fonte_fora(awesomeapi, status: 503)
      inventado = fonte_responde(brasilapi, da_brasilapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')['situacao']).to eq('nao_consegui_consultar')
      expect(inventado).not_to have_been_requested
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(sem_resposta: 1, nao_encontradas: 0)
    end

    it 'erro de transporte na principal (linha de status quebrada) cai na reserva' do
      allow(SafeFetch).to receive(:fetch).and_call_original
      allow(SafeFetch).to receive(:fetch).with(viacep, anything).and_raise(Net::HTTPBadResponse, 'wrong status line')
      fonte_responde(awesomeapi, da_awesomeapi)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')['dados']).to eq(esperado)
      expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('viacep.falha_de_rede' => 1)
    end

    it 'o nao encontrado fica uma hora no cache e nao gasta a fonte de novo' do
      loja = cache_em_memoria
      allow(loja).to receive(:write).and_call_original
      principal = fonte_responde(viacep, { erro: true })
      fonte_fora(awesomeapi, status: 404)

      2.times { expect(executar_pronta(ferramenta, 'cep' => '01001000')['situacao']).to eq('nao_encontrado') }

      expect(principal).to have_been_requested.once
      expect(loja).to have_received(:write).with(anything, { 'situacao' => 'nao_encontrado' }, expires_in: 1.hour)
    end

    it 'com o cache fora do ar, consulta a fonte do mesmo jeito' do
      allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError)
      allow(Rails.cache).to receive(:write).and_raise(Redis::CannotConnectError)
      fonte_responde(viacep, do_viacep)

      expect(executar_pronta(ferramenta, 'cep' => '01001000')['dados']).to eq(esperado)
    end

    it 'com as tres fora, diz que nao conseguiu consultar e nao inventa' do
      fonte_lenta(viacep)
      fonte_fora(awesomeapi, status: 503)
      fonte_fora(brasilapi, status: 500)

      saida = executar_pronta(ferramenta, 'cep' => '01001000')

      expect(saida).to eq('situacao' => 'nao_consegui_consultar', 'orientacao' => Autonomia::FerramentasProntas::Resposta::NAO_CONSEGUI)
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(
        sem_resposta: 1, motivos: { 'viacep.tempo_esgotado' => 1, 'awesomeapi.erro_da_fonte' => 1, 'brasilapi.erro_da_fonte' => 1 }
      )
    end

    it 'recusa CEP fora do formato sem chamar fonte nenhuma' do
      saida = executar_pronta(ferramenta, 'cep' => '0100-100')

      expect(saida).to include('situacao' => 'pedido_invalido', 'campo' => 'cep')
      expect(a_request(:get, /brasilapi|viacep|awesomeapi/)).not_to have_been_made
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(consultas: 0, recusadas: 1, motivos: { 'pedido_invalido' => 1 })
    end
  end

  describe 'CNPJ (BrasilAPI, depois Minha Receita, depois OpenCNPJ)' do
    let(:ferramenta) { incluir_pronta('cnpj', conta: account, agente: agent) }
    let(:cnpj) { '33000167000101' }
    let(:brasilapi) { "https://brasilapi.com.br/api/cnpj/v1/#{cnpj}" }
    let(:minhareceita) { "https://minhareceita.org/#{cnpj}" }
    let(:opencnpj) { "https://api.opencnpj.org/#{cnpj}" }
    let(:da_receita) do
      { cnpj: cnpj, razao_social: 'EMPRESA EXEMPLO S A', nome_fantasia: 'EXEMPLO', descricao_situacao_cadastral: 'ATIVA',
        data_situacao_cadastral: '2005-11-03', data_inicio_atividade: '1966-09-28', cnae_fiscal: 600_001,
        cnae_fiscal_descricao: 'Extração de petróleo e gás natural', natureza_juridica: 'Sociedade de Economia Mista',
        porte: 'DEMAIS', municipio: 'RIO DE JANEIRO', uf: 'RJ', email: 'contato@exemplo.test', ddd_telefone_1: '2100000000',
        qsa: [{ nome_socio: 'PESSOA SOCIA', cnpj_cpf_do_socio: '***000000**' }] }
    end

    it 'responde pela principal so com o que identifica a empresa, sem socio, e-mail nem telefone' do
      fonte_responde(brasilapi, da_receita)

      saida = executar_pronta(ferramenta, 'cnpj' => '33.000.167/0001-01')

      expect(saida['dados']).to eq(
        'cnpj' => '33.000.167/0001-01', 'razao_social' => 'EMPRESA EXEMPLO S A', 'nome_fantasia' => 'EXEMPLO',
        'situacao' => 'ATIVA', 'data_da_situacao' => '2005-11-03', 'abertura' => '1966-09-28',
        'natureza_juridica' => 'Sociedade de Economia Mista', 'porte' => 'DEMAIS', 'cidade' => 'RIO DE JANEIRO', 'uf' => 'RJ',
        'atividade_principal' => { 'codigo' => '0600001', 'descricao' => 'Extração de petróleo e gás natural' }
      )
      expect(saida.to_json).not_to include('PESSOA SOCIA', 'contato@exemplo.test', '2100000000')
    end

    it 'vai a segunda reserva quando as duas primeiras falham' do
      fonte_lenta(brasilapi)
      fonte_responde(minhareceita, '<html>erro</html>', tipo: 'text/html')
      fonte_responde(opencnpj, { cnpj: cnpj, razao_social: 'EMPRESA EXEMPLO S A', situacao_cadastral: 'Ativa',
                                 cnaes: [{ codigo: '0600001', descricao: 'Extração', is_principal: true }],
                                 telefones: [{ ddd: '21', numero: '00000000' }] })

      saida = executar_pronta(ferramenta, 'cnpj' => cnpj)

      expect(saida['dados']).to include('razao_social' => 'EMPRESA EXEMPLO S A', 'situacao' => 'ATIVA',
                                        'atividade_principal' => { 'codigo' => '0600001', 'descricao' => 'Extração' })
      expect(saida.to_json).not_to include('00000000')
      expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('brasilapi.tempo_esgotado' => 1, 'minhareceita.resposta_invalida' => 1)
    end

    it 'recusa CNPJ com digito verificador errado sem chamar fonte' do
      expect(executar_pronta(ferramenta, 'cnpj' => '33.000.167/0001-02')).to include('situacao' => 'pedido_invalido', 'campo' => 'cnpj')
      expect(a_request(:get, /brasilapi|minhareceita|opencnpj/)).not_to have_been_made
    end

    it 'aceita o CNPJ alfanumerico e o manda em maiusculas' do
      pedido = fonte_responde('https://brasilapi.com.br/api/cnpj/v1/12ABC34501DE35', da_receita.merge(cnpj: '12ABC34501DE35'))

      expect(executar_pronta(ferramenta, 'cnpj' => '12.abc.345/01de-35')['dados']['cnpj']).to eq('12.ABC.345/01DE-35')
      expect(pedido).to have_been_requested.once
    end

    it 'com as tres fora, diz que nao conseguiu consultar' do
      [brasilapi, minhareceita, opencnpj].each { |url| fonte_fora(url) }

      expect(executar_pronta(ferramenta, 'cnpj' => cnpj)['situacao']).to eq('nao_consegui_consultar')
    end
  end

  describe 'FIPE (BrasilAPI, reserva parallelum)' do
    let(:ferramenta) { incluir_pronta('fipe', conta: account, agente: agent) }
    let(:preco_brasilapi) { 'https://brasilapi.com.br/api/fipe/preco/v1/004517-9' }
    let(:anos_parallelum) { 'https://parallelum.com.br/fipe/api/v2/cars/004517-9/years' }
    let(:preco_parallelum) { 'https://parallelum.com.br/fipe/api/v2/cars/004517-9/years/2020-5' }
    let(:da_parallelum) do
      { vehicleType: 1, price: 'R$ 56.043,00', brand: 'GM - Chevrolet', model: 'ONIX HATCH LT 1.0 12V Flex 5p Mec.',
        modelYear: 2020, fuel: 'Flex', codeFipe: '004517-9', referenceMonth: 'novembro de 2026', fuelAcronym: 'F' }
    end
    let(:preco_esperado) do
      { 'valor' => 56_043.0, 'marca' => 'GM - Chevrolet', 'modelo' => 'ONIX HATCH LT 1.0 12V Flex 5p Mec.',
        'ano_modelo' => 2020, 'combustivel' => 'Flex', 'codigo_fipe' => '004517-9', 'mes_de_referencia' => '2026-11' }
    end

    # O código do modelo só vale se está na lista da marca (o "208" da Peugeot é nome): a lista da GM, com o 8949.
    before do
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models', [{ code: '8949', name: 'ONIX HATCH LT 1.0 12V Flex 5p Mec.' }])
    end

    it 'lista as marcas pela principal' do
      fonte_responde('https://brasilapi.com.br/api/fipe/marcas/v1/carros', [{ nome: 'Acura', valor: '1' }, { nome: 'GM - Chevrolet', valor: '23' }])

      saida = executar_pronta(ferramenta, 'consulta' => 'marcas', 'tipo' => 'carros')

      expect(saida['dados']).to eq('marcas' => [{ 'codigo' => '1', 'nome' => 'Acura' }, { 'codigo' => '23', 'nome' => 'GM - Chevrolet' }],
                                   'total' => 2)
    end

    it 'da o preco pela principal, filtrado pelo ano' do
      fonte_responde(preco_brasilapi, [
                       { valor: 'R$ 56.043,00', marca: 'GM - Chevrolet', modelo: 'ONIX HATCH LT 1.0 12V Flex 5p Mec.', anoModelo: 2020,
                         combustivel: 'Flex', codigoFipe: '004517-9', mesReferencia: 'novembro de 2026 ' },
                       { valor: 'R$ 60.000,00', anoModelo: 2021, codigoFipe: '004517-9' }
                     ])

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'codigo_fipe' => '0045179', 'ano' => '2020')

      expect(saida['dados']).to eq('precos' => [preco_esperado], 'unidades' => { 'valor' => 'R$' })
    end

    it 'cai na reserva (anos e depois o preco) quando a principal esta fora' do
      fonte_fora(preco_brasilapi)
      fonte_responde(anos_parallelum, [{ code: '2020-5', name: '2020 Flex' }, { code: '2021-5', name: '2021 Flex' }])
      fonte_responde(preco_parallelum, da_parallelum)

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'codigo_fipe' => '004517-9', 'ano' => 2020)

      expect(saida['dados']).to eq('precos' => [preco_esperado], 'unidades' => { 'valor' => 'R$' })
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(pela_reserva: 1, motivos: { 'brasilapi.erro_da_fonte' => 1 })
    end

    # Revisão do #2906: o preço sem valor que se leia ia ao agente sem o valor; agora é falha, e a reserva tenta.
    it 'o preco sem valor legivel na principal e falha, e a reserva responde' do
      fonte_responde(preco_brasilapi, [{ valor: 'indisponível', anoModelo: 2020, codigoFipe: '004517-9' }])
      fonte_responde(anos_parallelum, [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde(preco_parallelum, da_parallelum)

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'codigo_fipe' => '004517-9', 'ano' => 2020)

      expect(saida['dados']).to eq('precos' => [preco_esperado], 'unidades' => { 'valor' => 'R$' })
      expect(Autonomia::FerramentasProntas::Uso.sole).to have_attributes(pela_reserva: 1, motivos: { 'brasilapi.resposta_invalida' => 1 })
    end

    it 'com a chave gratuita no ambiente, a parallelum recebe o cabecalho; sem ela, nada vai' do
      anos = 'https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years'
      fonte_responde(anos, [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde("#{anos}/2020-5", da_parallelum)
      pedido = { 'consulta' => 'preco', 'tipo' => 'carros', 'marca' => '23', 'modelo' => '8949', 'ano' => 2020 }
      com_chave = ->(req) { req.headers.key?('X-Subscription-Token') }

      with_modified_env(AUTONOMIA_PRONTAS_FIPE_TOKEN: '') { executar_pronta(ferramenta, pedido) }
      expect(a_request(:get, anos).with(&com_chave)).not_to have_been_made

      with_modified_env(AUTONOMIA_PRONTAS_FIPE_TOKEN: 'chave-de-teste') { executar_pronta(ferramenta, pedido) }
      expect(a_request(:get, anos).with(headers: { 'X-Subscription-Token' => 'chave-de-teste' })).to have_been_made.once
      expect(a_request(:get, "#{anos}/2020-5").with(headers: { 'X-Subscription-Token' => 'chave-de-teste' })).to have_been_made.once
    end

    it 'por marca e modelo vai direto a parallelum, que e a unica que atende' do
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years', [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years/2020-5', da_parallelum)

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'marca' => '23', 'modelo' => '8949', 'ano' => 2020)

      expect(saida['dados']).to eq('precos' => [preco_esperado], 'unidades' => { 'valor' => 'R$' })
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
      expect(Autonomia::FerramentasProntas::Uso.sole.pela_reserva).to eq(0)
    end

    it 'sem o ano, devolve os anos que existem e o preco de um ano so quando so ha um' do
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years', [{ code: '2020-5', name: '2020 Flex' }])
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years/2020-5', da_parallelum)

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'marca' => '23', 'modelo' => '8949')

      expect(saida['dados']).to include('anos_disponiveis' => ['2020 Flex'], 'precos' => [preco_esperado])
    end

    it 'filtra os modelos pela busca, que nunca vai a fonte' do
      modelos = [{ code: '8949', name: 'ONIX HATCH LT 1.0 12V Flex 5p Mec.' }, { code: '1', name: 'CRUZE LT' }]
      pedido = fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models', modelos)

      saida = executar_pronta(ferramenta, 'consulta' => 'modelos', 'tipo' => 'carros', 'marca' => '23', 'busca' => 'onix lt')

      expect(saida['dados']).to eq('modelos' => [{ 'codigo' => '8949', 'nome' => 'ONIX HATCH LT 1.0 12V Flex 5p Mec.' }], 'total' => 1)
      expect(pedido).to have_been_requested.once
    end

    it 'guarda a lista inteira da marca: outra busca vem do cache, sem chamar a fonte' do
      cache_em_memoria
      modelos = [{ code: '8949', name: 'ONIX HATCH LT 1.0' }, { code: '1', name: 'CRUZE LT' }]
      pedido = fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models', modelos)
      pedir = ->(busca) { executar_pronta(ferramenta, 'consulta' => 'modelos', 'tipo' => 'carros', 'marca' => '23', 'busca' => busca) }

      expect(pedir.call('onix')['dados']['modelos'].pluck('codigo')).to eq(['8949'])
      expect(pedir.call('cruze')['dados']['modelos'].pluck('codigo')).to eq(['1'])
      expect(pedir.call('fusca')['situacao']).to eq('nao_encontrado')
      expect(pedido).to have_been_requested.once
    end

    it 'lista que vem como objeto e falha da fonte, nao "nao encontrado", e a reserva responde' do
      fonte_responde('https://brasilapi.com.br/api/fipe/marcas/v1/carros', { message: 'fora' })
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands', [{ code: '23', name: 'GM - Chevrolet' }])

      saida = executar_pronta(ferramenta, 'consulta' => 'marcas', 'tipo' => 'carros')

      expect(saida['dados']['marcas']).to eq([{ 'codigo' => '23', 'nome' => 'GM - Chevrolet' }])
      expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('brasilapi.resposta_invalida' => 1)
    end

    it 'codigo de ano fora do formato, vindo da fonte, nunca volta ao caminho' do
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years',
                     [{ code: '2020-5/../../x', name: '2020' }, { code: '2020-5', name: '2020 Flex' }])
      fonte_responde('https://parallelum.com.br/fipe/api/v2/cars/brands/23/models/8949/years/2020-5', da_parallelum)

      saida = executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'marca' => '23', 'modelo' => '8949', 'ano' => 2020.0)

      expect(saida['dados']['precos'].size).to eq(1)
      expect(a_request(:get, /x$/)).not_to have_been_made
    end

    it 'preco sem codigo nem marca e modelo e pedido invalido na marca (nunca no codigo FIPE)' do
      expect(executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'ano' => 2020))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'marca')
    end

    it 'consulta fora da lista e pedido invalido' do
      expect(executar_pronta(ferramenta, 'consulta' => 'placa', 'tipo' => 'carros'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'consulta')
    end

    it 'com as duas fora, diz que nao conseguiu consultar' do
      fonte_fora(preco_brasilapi)
      fonte_lenta(anos_parallelum)

      expect(executar_pronta(ferramenta, 'consulta' => 'preco', 'tipo' => 'carros', 'codigo_fipe' => '004517-9', 'ano' => 2020)['situacao'])
        .to eq('nao_consegui_consultar')
    end
  end
end

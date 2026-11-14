require 'rails_helper'

# #2993: o veículo pela placa ou pelo chassi, dentro do card do carro (FIPE), pelo caminho real (a `Execucao` da
# ferramenta pronta de um agente), com o WebMock no lugar da fonte parceira e da FIPE. A placa, o chassi, o cadastro e
# os valores são inventados.
RSpec.describe Autonomia::FerramentasProntas::Fontes do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:ferramenta) { incluir_pronta('fipe', conta: account, agente: agent) }
  let(:fipe) { Autonomia::FerramentasProntas::Fontes::Fipe }
  let(:passe) { 'https://passe.exemplo.test/bilhete?de=teste' }
  let(:entrada) { 'https://veiculos.exemplo.test/acesso' }
  let(:placa) { 'https://veiculos.exemplo.test/veiculo/placa/ABC1D23' }
  let(:chassi) { 'https://veiculos.exemplo.test/veiculo/chassi/9BWZZZ377VT004251' }
  let(:preco) { 'https://brasilapi.com.br/api/fipe/preco/v1/002224-1' }
  let(:fonte) do
    { passe: passe, entrada: entrada, placa: 'https://veiculos.exemplo.test/veiculo/placa/',
      chassi: 'https://veiculos.exemplo.test/veiculo/chassi/', corpo: { cadastro: 'ab12', documento: '11222333000181' } }
  end
  let(:cadastro) { { PRONTAS_VEICULO_FONTE: fonte.to_json } }
  let(:da_placa) do
    { manufacturing_year: 2025, model: 'Toyota - YARIS Cross XRX 1.5 16V 5p Aut.', chassi: '9BWZZZ377VT004251', plate: 'ABC1D23',
      model_year: 2026, brand: 'Toyota',
      fipes_info: [{ fipe_code: '002224-1', description: 'Toyota - YARIS Cross XRX 1.5 16V 5p Aut.', fipe_price: 150_000 }] }
  end
  let(:do_chassi) { [{ brand: 'Toyota', model: 'YARIS Cross XRX 1.5 16V 5p Aut.', year: 2026, fipe: '002224-1', plate: 'ABC1D23' }] }
  let(:da_fipe) do
    [{ valor: 'R$ 163.320,00', marca: 'Toyota', modelo: 'YARIS Cross XRX 1.5 16V 5p Aut.', anoModelo: 2026, combustivel: 'Flex',
       codigoFipe: '002224-1', mesReferencia: 'novembro de 2026' }]
  end

  before do
    resolver_hosts_das_prontas
    allow(Resolv).to receive(:getaddresses).with('passe.exemplo.test').and_return(['93.184.216.67'])
    allow(Resolv).to receive(:getaddresses).with('veiculos.exemplo.test').and_return(['93.184.216.66'])
    ligar_prontas(account)
    provedor.esquecer_acesso!
  end

  def provedor
    fipe::PelaPlaca
  end

  def veiculo(argumentos)
    executar_pronta(ferramenta, { 'consulta' => 'veiculo' }.merge(argumentos))
  end

  def entrar_responde(acesso = 'acesso-1')
    fonte_responde(passe, { token: 'passe-1' })
    stub_request(:post, entrada).with(body: { 'cadastro' => 'ab12', 'documento' => '11222333000181', 'token' => 'passe-1' })
                                .to_return(status: 200, body: { token: acesso }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  def fonte_recusa(url, status, erro)
    stub_request(:get, url).to_return(status: status, body: { error: erro }.to_json, headers: { 'Content-Type' => 'application/json' })
  end

  describe 'com o cadastro da plataforma no ambiente' do
    around { |example| with_modified_env(cadastro) { example.run } }

    before { entrar_responde }

    it 'pela placa: marca, modelo, anos, tipo e a versao com o valor do mes da FIPE (nao o valor que a fonte devolve)' do
      consulta = stub_request(:get, placa).with(headers: { 'Authorization' => 'Bearer acesso-1' })
                                          .to_return(status: 200, body: da_placa.to_json, headers: { 'Content-Type' => 'application/json' })
      fonte_responde(preco, da_fipe)

      saida = veiculo('placa' => 'abc-1d23')

      expect(saida).to include('situacao' => 'encontrado', 'consulta' => 'veiculo')
      expect(saida['dados']).to eq(
        'placa' => 'ABC1D23', 'chassi' => '9BWZZZ377VT004251',
        'marca' => 'Toyota', 'modelo' => 'YARIS Cross XRX 1.5 16V 5p Aut.', 'tipo' => 'carros', 'ano_fabricacao' => 2025, 'ano_modelo' => 2026,
        'versoes' => [{ 'codigo_fipe' => '002224-1', 'descricao' => 'YARIS Cross XRX 1.5 16V 5p Aut.', 'valor' => 163_320.0,
                        'combustivel' => 'Flex', 'mes_de_referencia' => '2026-11' }],
        'unidades' => { 'valor' => 'R$' }
      )
      expect(consulta).to have_been_made.once
    end

    it 'a placa e o chassi vao os dois na resposta, venha o pedido por um ou pelo outro' do
      fonte_responde(placa, da_placa)
      fonte_responde(chassi, do_chassi)
      fonte_responde(preco, da_fipe)

      pela_placa = veiculo('placa' => 'ABC1D23')['dados']
      pelo_chassi = veiculo('chassi' => '9bw zzz377 vt004251')['dados']

      expect(pela_placa).to include('placa' => 'ABC1D23', 'chassi' => '9BWZZZ377VT004251')
      expect(pelo_chassi).to include('placa' => 'ABC1D23', 'chassi' => '9BWZZZ377VT004251')
    end

    it 'pelo chassi: a lista devolve a placa, e a placa devolve o veiculo inteiro, na mesma ida' do
      fonte_responde(chassi, do_chassi)
      fonte_responde(placa, da_placa)
      fonte_responde(preco, da_fipe)

      saida = veiculo('chassi' => '9BWZZZ377VT004251')

      expect(saida['dados']).to include('marca' => 'Toyota', 'ano_fabricacao' => 2025, 'ano_modelo' => 2026, 'tipo' => 'carros')
      expect(saida['dados']['versoes'].first).to include('codigo_fipe' => '002224-1', 'valor' => 163_320.0)
      expect(a_request(:get, chassi)).to have_been_made.once
      expect(a_request(:get, placa)).to have_been_made.once
    end

    it 'pelo chassi de um carro ainda sem placa: vale o resumo, com o codigo FIPE e o valor' do
      fonte_responde(chassi, [do_chassi.first.merge(plate: nil)])
      fonte_responde(preco, da_fipe)

      saida = veiculo('chassi' => '9BWZZZ377VT004251')

      expect(saida['dados']).to include('chassi' => '9BWZZZ377VT004251', 'marca' => 'Toyota',
                                        'modelo' => 'YARIS Cross XRX 1.5 16V 5p Aut.', 'ano_modelo' => 2026)
      expect(saida['dados'].keys).not_to include('ano_fabricacao', 'placa')
      expect(saida['dados']['versoes']).to eq([{ 'codigo_fipe' => '002224-1', 'valor' => 163_320.0, 'combustivel' => 'Flex',
                                                 'mes_de_referencia' => '2026-11' }])
      expect(a_request(:get, %r{/veiculo/placa/})).not_to have_been_made
    end

    it 'mais de uma versao na placa: as duas com valor e o aviso de que cada uma tem o seu' do
      outra = { fipe_code: '002225-0', description: 'Toyota - YARIS Cross XRS 1.5 16V 5p Aut.', fipe_price: 180_000 }
      fonte_responde(placa, da_placa.merge(fipes_info: da_placa[:fipes_info] + [outra]))
      fonte_responde(preco, da_fipe)
      fonte_responde('https://brasilapi.com.br/api/fipe/preco/v1/002225-0', [da_fipe.first.merge(valor: 'R$ 171.000,00', codigoFipe: '002225-0')])

      dados = veiculo('placa' => 'ABC1D23')['dados']

      expect(dados['versoes'].pluck('codigo_fipe', 'valor')).to eq([['002224-1', 163_320.0], ['002225-0', 171_000.0]])
      expect(dados['observacao']).to eq(provedor::VARIAS_VERSOES)
    end

    it 'o tipo sai do codigo FIPE: 8 e moto, 5 e caminhao, e outro comeco vai sem tipo' do
      tipos = { '811131-8' => 'motos', '509293-0' => 'caminhoes', '302004-5' => nil }.map do |codigo, _tipo|
        provedor.esquecer_acesso!
        fonte_responde(placa, da_placa.merge(fipes_info: [{ fipe_code: codigo, description: 'Modelo' }]))
        fonte_responde("https://brasilapi.com.br/api/fipe/preco/v1/#{codigo}", [da_fipe.first.merge(codigoFipe: codigo)])
        cache_em_memoria
        veiculo('placa' => 'ABC1D23')['dados']['tipo']
      end

      expect(tipos).to eq(['motos', 'caminhoes', nil])
    end

    it 'veículo não encontrado: orienta o agente e avisa o status sem expor os dados consultados' do
      avisos = []
      allow(Rails.logger).to receive(:warn) { |mensagem| avisos << mensagem }
      fonte_recusa(placa, 400, 'nao achei')
      fonte_recusa(chassi, 450, 'nao achei')

      pela_placa = veiculo('placa' => 'ABC1D23')
      pelo_chassi = veiculo('chassi' => '9BWZZZ377VT004251')

      expect(pela_placa).to include('situacao' => 'nao_encontrado', 'orientacao' => fipe::VEICULO_NAO_ENCONTRADO)
      expect(pelo_chassi).to include('situacao' => 'nao_encontrado', 'orientacao' => fipe::VEICULO_NAO_ENCONTRADO)
      expect(a_request(:get, /brasilapi|parallelum/)).not_to have_been_made
      # Só os avisos deste provedor: o cliente HTTP também avisa, uma vez por processo, quando roda sem teto por leitura.
      expect(avisos.select { |aviso| aviso.include?(provedor::NOME) })
        .to eq(['[autonomia][pronta] veiculo_pela_placa não encontrado status=400',
                '[autonomia][pronta] veiculo_pela_placa não encontrado status=450'])
    end

    it 'sem placa e sem chassi, ou com a placa fora do formato: pedido invalido na placa, e nada sai para a rede' do
      expect(veiculo({})).to include('situacao' => 'pedido_invalido', 'campo' => 'placa')
      expect(veiculo('placa' => 'ABC12')).to include('situacao' => 'pedido_invalido', 'campo' => 'placa')
      expect(veiculo('chassi' => '9BWZZZ377VT00425I')).to include('situacao' => 'pedido_invalido', 'campo' => 'chassi')
      expect(a_request(:any, /veiculos|passe/)).not_to have_been_made
    end

    it 'o acesso fica guardado: a segunda placa nao pede o passe nem entra de novo' do
      fonte_responde(placa, da_placa)
      fonte_responde('https://veiculos.exemplo.test/veiculo/placa/XYZ9A88', da_placa)
      fonte_responde(preco, da_fipe)

      veiculo('placa' => 'ABC1D23')
      veiculo('placa' => 'XYZ9A88')

      expect(a_request(:get, passe)).to have_been_made.once
      expect(a_request(:post, entrada)).to have_been_made.once
    end

    it 'o acesso que venceu (401): entra de novo uma vez e responde' do
      stub_request(:get, placa).to_return(
        { status: 401, body: { error: 'sem acesso' }.to_json, headers: { 'Content-Type' => 'application/json' } },
        { status: 200, body: da_placa.to_json, headers: { 'Content-Type' => 'application/json' } }
      )
      fonte_responde(preco, da_fipe)

      expect(veiculo('placa' => 'ABC1D23')['situacao']).to eq('encontrado')
      expect(a_request(:post, entrada)).to have_been_made.twice
      expect(a_request(:get, placa)).to have_been_made.twice
    end

    it 'a entrada recusada (400) nunca vira "nao achei o veiculo": nao consegui, com o motivo da entrada' do
      stub_request(:post, entrada).to_return(status: 400, body: { error: 'invalid' }.to_json, headers: { 'Content-Type' => 'application/json' })

      saida = veiculo('placa' => 'ABC1D23')

      expect(saida['situacao']).to eq('nao_consegui_consultar')
      expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('veiculo_pela_placa.entrada.pedido_recusado' => 1)
      expect(a_request(:get, %r{/veiculo/})).not_to have_been_made
    end

    it 'a FIPE fora do ar nao derruba a consulta: o veiculo vai sem o valor, e essa resposta nao fica no cache' do
      cache_em_memoria
      fonte_responde(placa, da_placa)
      fonte_fora(preco)
      fonte_fora(/parallelum/)

      saida = veiculo('placa' => 'ABC1D23')
      veiculo('placa' => 'ABC1D23')

      expect(saida['situacao']).to eq('encontrado')
      expect(saida['dados']['versoes']).to eq([{ 'codigo_fipe' => '002224-1', 'descricao' => 'YARIS Cross XRX 1.5 16V 5p Aut.' }])
      expect(saida['dados']).not_to have_key('unidades')
      expect(a_request(:get, placa)).to have_been_made.twice
    end

    it 'com o valor, a resposta fica no cache: a mesma placa de novo nao vai a fonte' do
      cache_em_memoria
      fonte_responde(placa, da_placa)
      fonte_responde(preco, da_fipe)

      2.times { veiculo('placa' => 'ABC1D23') }

      expect(a_request(:get, placa)).to have_been_made.once
    end

    it 'o modelo ve a consulta veiculo, com placa e chassi opcionais' do
      schema = fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: 'o cliente informar a placa')

      expect(schema[:parameters][:properties]['consulta']['enum']).to eq(%w[marcas modelos preco veiculo])
      expect(schema[:parameters][:properties]).to include('placa' => include('type' => %w[string null]),
                                                          'chassi' => include('type' => %w[string null]))
    end

    it 'o schema aceita tipo nulo, mas marcas, modelos e preço continuam exigindo tipo' do
      schema = fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: '')

      expect(schema[:parameters][:properties]['tipo']['type']).to eq(%w[string null])
      %w[marcas modelos preco].each do |nome|
        expect(fipe::FONTE.consulta(nome).conferir({}).last.campo).to eq('tipo')
      end
    end

    it 'a descrição instrui o agente a guardar os identificadores só para a equipe' do
      schema = fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: '')

      expect(schema[:description]).to include(
        'A placa e o chassi devolvidos são para o registro da equipe.',
        'Nunca diga ao cliente o chassi, nem a placa achada pelo chassi'
      )
    end

    it 'inspect e to_s escondem o cadastro e o acesso usados na consulta' do
      fonte_responde(placa, da_placa)
      fonte_responde(preco, da_fipe)
      cliente = Autonomia::FerramentasProntas::ClienteHttp.new(hosts: [],
                                                               prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + 5)
      consulta = provedor.new(cliente, prazo: 3)
      consulta.consultar(nil, 'placa' => 'ABC1D23')

      expect(consulta.inspect).to eq("#<#{provedor.name} [REDACTED]>")
      expect(consulta.to_s).to eq(consulta.inspect)
    end

    it 'com o host da consulta desligado, nem a entrada sai para a rede' do
      with_modified_env(AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS: 'veiculos.exemplo.test') do
        saida = veiculo('placa' => 'ABC1D23')

        expect(saida['situacao']).to eq('nao_consegui_consultar')
        expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('veiculo_pela_placa.provedor_desligado' => 1)
        expect(a_request(:any, ->(uri) { %w[veiculos.exemplo.test passe.exemplo.test].include?(uri.host) })).not_to have_been_made
      end
    end

    it 'o login so sai pelo IP do servidor: o POST a um host que nao e de cadastro e recusado' do
      cliente = Autonomia::FerramentasProntas::ClienteHttp.new(hosts: ['veiculos.exemplo.test'], conta: account.id,
                                                               prazo_final: Autonomia::FerramentasProntas::ClienteHttp.agora + 5)

      expect { cliente.post_json('veiculos.exemplo.test', '/acesso', {}, prazo: 2) }
        .to raise_error(Autonomia::FerramentasProntas::Provedor::Falha, 'endereco_recusado')
      expect(a_request(:post, entrada)).not_to have_been_made
    end
  end

  describe 'sem o cadastro da plataforma no ambiente' do
    around { |example| with_modified_env(PRONTAS_VEICULO_FONTE: nil) { example.run } }

    it 'a consulta nao e oferecida: o card segue com marcas, modelos e preco' do
      schema = fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: 'o cliente perguntar o valor')

      expect(fipe::FONTE.consultas.map(&:nome)).to eq(%w[marcas modelos preco])
      expect(schema[:parameters][:properties].keys).not_to include('placa', 'chassi')
      expect(schema[:parameters][:properties]['tipo']['type']).to eq('string')
    end

    it 'o schema exige tipo como string nas três consultas restantes' do
      schema = fipe::FONTE.openai_schema(slug: 'pronta_fipe', usar_quando: '')

      expect(schema[:parameters][:properties]['tipo']['type']).to eq('string')
      expect(schema[:parameters][:properties]['tipo']['enum']).to eq(fipe::TIPOS)
      %w[marcas modelos preco].each do |nome|
        expect(fipe::FONTE.consulta(nome).conferir({}).last.campo).to eq('tipo')
      end
    end

    it 'a variável ausente não gera aviso' do
      allow(Rails.logger).to receive(:warn)

      3.times { provedor.cadastro }

      expect(Rails.logger).not_to have_received(:warn)
    end

    it 'o pedido de veiculo que chegar mesmo assim e recusado, sem ir a rede' do
      expect(veiculo('placa' => 'ABC1D23')).to include('situacao' => 'pedido_invalido', 'campo' => 'consulta')
      expect(a_request(:any, /veiculos|passe/)).not_to have_been_made
    end

    it 'o cadastro que nao vale deixa o provedor sem ele: sem HTTPS, fora da 443, com usuario, sem a barra, sem corpo' do
      ruins = [fonte.merge(passe: 'http://passe.exemplo.test/bilhete').to_json, fonte.merge(corpo: {}).to_json,
               fonte.except(:chassi).to_json, 'nao e json',
               fonte.merge(entrada: 'https://veiculos.exemplo.test:8443/acesso').to_json,
               fonte.merge(entrada: 'https://alguem:senha@veiculos.exemplo.test/acesso').to_json,
               fonte.merge(placa: 'https://veiculos.exemplo.test/veiculo/placa').to_json]

      configurados = ruins.map { |valor| with_modified_env(PRONTAS_VEICULO_FONTE: valor) { provedor.configurado? } }

      expect(configurados).to all(be(false))
      expect(with_modified_env(cadastro) { provedor.configurado? }).to be(true)
    end
  end

  describe 'aviso de cadastro inválido' do
    around do |example|
      avisado = provedor.instance_variable_get(:@cadastro_avisado)
      provedor.instance_variable_set(:@cadastro_avisado, nil)
      example.run
    ensure
      provedor.instance_variable_set(:@cadastro_avisado, avisado)
    end

    { 'json' => 'PRONTAS_VEICULO_FONTE', 'objeto' => 'PRONTAS_VEICULO_FONTE',
      'corpo_ausente' => 'corpo', 'corpo_vazio' => 'corpo', 'corpo_invalido' => 'corpo', 'passe' => 'passe',
      'porta' => 'entrada', 'host' => 'entrada', 'usuario' => 'entrada', 'placa' => 'placa', 'chassi' => 'chassi',
      'endereco_ausente' => 'chassi' }.each do |caso, campo|
      it "avisa uma vez, só com o nome do campo: #{caso}" do
        invalidos = {
          'json' => 'cadastro-secreto-inválido', 'objeto' => ['segredo'].to_json,
          'corpo_ausente' => fonte.except(:corpo).to_json, 'corpo_vazio' => fonte.merge(corpo: {}).to_json,
          'corpo_invalido' => fonte.merge(corpo: 'segredo').to_json,
          'passe' => fonte.merge(passe: 'http://passe.exemplo.test/bilhete').to_json,
          'porta' => fonte.merge(entrada: 'https://veiculos.exemplo.test:8443/acesso').to_json,
          'host' => fonte.merge(entrada: 'https:/acesso').to_json,
          'usuario' => fonte.merge(entrada: 'https://alguem:segredo@veiculos.exemplo.test/acesso').to_json,
          'placa' => fonte.merge(placa: 'https://veiculos.exemplo.test/placa').to_json,
          'chassi' => fonte.merge(chassi: 'https://veiculos.exemplo.test/chassi').to_json,
          'endereco_ausente' => fonte.except(:chassi).to_json
        }
        avisos = []
        allow(Rails.logger).to receive(:warn) { |mensagem| avisos << mensagem }

        with_modified_env(PRONTAS_VEICULO_FONTE: invalidos.fetch(caso)) do
          expect(Array.new(3) { provedor.cadastro }).to eq([nil, nil, nil])
        end

        expect(avisos).to eq(["[autonomia][pronta] veiculo_pela_placa cadastro inválido campo=#{campo}"])
      end
    end
  end
end

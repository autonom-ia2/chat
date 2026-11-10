require 'rails_helper'

# #2858 (F1): as consultas mais usadas — CPF, feriados e dias úteis, Banco Central, cidades e estados, DDD, localização
# e bancos. Cada uma pelo caminho real (a `Execucao` da ferramenta pronta de um agente), com o WebMock no lugar da
# fonte: a resposta boa (a pergunta de aceite do plano), a reserva com a principal fora e "não consegui" com todas fora.
RSpec.describe Autonomia::FerramentasProntas::Execucao do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:uso) { Autonomia::FerramentasProntas::Uso.sole }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00')) { example.run } }

  def nao_consegui?(saida)
    saida['situacao'] == 'nao_consegui_consultar' && !saida.key?('dados')
  end

  describe 'a flag da F1' do
    it 'desligada, a fonte da F1 nao entra e nao consulta; CEP, CNPJ e FIPE seguem' do
      account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)
      ferramenta = incluir_pronta('cep', conta: account, agente: agent)

      expect { incluir_pronta('ddd', conta: account, agente: agent) }
        .to raise_error(Autonomia::FerramentasProntas::Incluir::Recusado, 'desligada')
      expect(Autonomia::FerramentasProntas.disponivel?(account, ferramenta.fonte_do_catalogo)).to be(true)
    end

    it 'desligada depois de incluir, a execucao responde "nao consegui" sem chamar ninguem' do
      ferramenta = incluir_pronta('bancos', conta: account, agente: agent)
      account.disable_features!(Autonomia::FerramentasProntas::FLAG_CONSULTAS)

      expect(nao_consegui?(executar_pronta(ferramenta, 'codigo' => '341'))).to be(true)
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
      expect(Autonomia::FerramentasProntas::Uso.count).to eq(0)
    end
  end

  describe 'CPF valido (calculado aqui)' do
    let(:ferramenta) { incluir_pronta('cpf', conta: account, agente: agent) }

    it 'confere o numero e a regiao fiscal, sem nome, sem chamada externa e sem guardar no cache' do
      loja = cache_em_memoria

      saida = executar_pronta(ferramenta, 'cpf' => '111.444.777-35')

      expect(saida['dados']).to include('valido' => true, 'regiao_fiscal' => '7ª região fiscal',
                                        'estados' => ['Espírito Santo', 'Rio de Janeiro'])
      expect(saida.to_json).not_to include('11144477735', '111.444.777')
      expect(WebMock::RequestRegistry.instance.requested_signatures.hash).to be_empty
      expect(loja.instance_variable_get(:@data)).to be_empty
    end

    it 'digito que nao confere e numero repetido: invalido, sem regiao' do
      expect(executar_pronta(ferramenta, 'cpf' => '111.444.777-36')['dados']).to include('valido' => false)
      expect(executar_pronta(ferramenta, 'cpf' => '111.111.111-11')['dados']).to include('valido' => false)
    end

    it 'sem os 11 digitos e pedido invalido, sem contar no limite' do
      expect(executar_pronta(ferramenta, 'cpf' => '1234')).to include('situacao' => 'pedido_invalido', 'campo' => 'cpf')
      expect(uso).to have_attributes(consultas: 0, recusadas: 1)
    end
  end

  describe 'Feriados e dias uteis (BrasilAPI, reserva Nager.Date, ultima reserva o calendario)' do
    let(:ferramenta) { incluir_pronta('feriados', conta: account, agente: agent) }
    let(:brasilapi) { 'https://brasilapi.com.br/api/feriados/v1/2026' }
    let(:nager) { 'https://date.nager.at/api/v3/PublicHolidays/2026/BR' }
    let(:da_brasilapi) do
      [{ date: '2026-11-15', name: 'Proclamação da República', type: 'national' },
       { date: '2026-11-20', name: 'Dia da consciência negra', type: 'national' }]
    end
    let(:do_nager) do
      [{ date: '2026-07-09', localName: 'Revolução Constitucionalista', global: false },
       { date: '2026-11-15', localName: 'Proclamação da República', global: true },
       { date: '2026-11-20', localName: 'Dia da Consciência Negra', global: true }]
    end

    it '"Quantos dias uteis ate 30/11?": conta de hoje, com os feriados nacionais' do
      fonte_responde(brasilapi, da_brasilapi)

      dados = executar_pronta(ferramenta, 'consulta' => 'dias_uteis', 'ate' => '30/11/2026')['dados']

      expect(dados).to include('de' => '2026-11-10', 'ate' => '2026-11-30', 'dias_uteis' => 14)
      expect(dados['feriados_no_periodo']).to eq([{ 'data' => '2026-11-20', 'nome' => 'Dia da consciência negra' }])
      expect(dados['regra']).to end_with('estaduais e municipais não entram.')
    end

    it 'com a principal fora, a Nager responde so com os feriados nacionais' do
      fonte_fora(brasilapi)
      fonte_responde(nager, do_nager)

      dados = executar_pronta(ferramenta, 'consulta' => 'feriados', 'ano' => 2026)['dados']

      expect(dados['feriados'].pluck('data')).to eq(%w[2026-11-15 2026-11-20])
      expect(uso).to have_attributes(pela_reserva: 1, motivos: { 'brasilapi.erro_da_fonte' => 1 })
    end

    it 'com as duas fora, o calendario calculado aqui responde (mesmas datas da lei)' do
      fonte_fora(brasilapi)
      fonte_lenta(nager)

      datas = executar_pronta(ferramenta, 'consulta' => 'feriados')['dados']['feriados'].pluck('data')

      expect(datas).to eq(%w[2026-01-01 2026-02-16 2026-02-17 2026-04-03 2026-04-05 2026-04-21 2026-05-01 2026-06-04
                             2026-09-07 2026-10-12 2026-11-02 2026-11-15 2026-11-20 2026-12-25])
    end

    it 'periodo ao contrario ou maior que dois anos e pedido invalido' do
      expect(executar_pronta(ferramenta, 'consulta' => 'dias_uteis', 'de' => '2026-12-01', 'ate' => '2026-11-30'))
        .to include('situacao' => 'pedido_invalido', 'campo' => 'ate')
      expect(executar_pronta(ferramenta, 'consulta' => 'dias_uteis', 'ate' => '2030-01-01')['campo']).to eq('ate')
    end
  end

  describe 'Banco Central (SGS e Olinda, reserva BrasilAPI e SGS)' do
    let(:ferramenta) { incluir_pronta('banco_central', conta: account, agente: agent) }
    let(:sgs) { ->(serie) { "https://api.bcb.gov.br/dados/serie/bcdata.sgs.#{serie}/dados/ultimos/1?formato=json" } }
    let(:ptax) { %r{\Ahttps://olinda\.bcb\.gov\.br/olinda/servico/PTAX/} }

    it '"Qual a Selic hoje?": a meta do Copom pelo SGS' do
      fonte_responde(sgs.call(432), [{ data: '10/11/2026', valor: '13.75' }])

      expect(executar_pronta(ferramenta, 'consulta' => 'selic')['dados'])
        .to eq('indicador' => 'Selic (meta do Copom)', 'valor' => 13.75, 'unidade' => '% ao ano')
    end

    it 'Selic com o SGS fora: a BrasilAPI responde' do
      fonte_fora(sgs.call(432), status: 503)
      fonte_responde('https://brasilapi.com.br/api/taxas/v1/selic', { nome: 'Selic', valor: 13.75 })

      expect(executar_pronta(ferramenta, 'consulta' => 'selic')['dados']['valor']).to eq(13.75)
      expect(uso.pela_reserva).to eq(1)
    end

    it '"E o dolar?": a PTAX do ultimo boletim; com a Olinda fora, as series do SGS' do
      boletins = [{ cotacaoCompra: 5.49, cotacaoVenda: 5.50, dataHoraCotacao: '2026-11-06 13:05:00' },
                  { cotacaoCompra: 5.514, cotacaoVenda: 5.5146, dataHoraCotacao: '2026-11-09 13:06:31' }]
      stub_request(:get, ptax).to_return(status: 200, body: { value: boletins }.to_json,
                                         headers: { 'Content-Type' => 'application/json;charset=UTF-8;odata.metadata=minimal' })

      expect(executar_pronta(ferramenta, 'consulta' => 'dolar')['dados'])
        .to include('compra' => 5.514, 'venda' => 5.5146, 'data' => '2026-11-09')
    end

    it 'dolar com a Olinda fora: compra e venda pelo SGS, com a data no mesmo formato' do
      stub_request(:get, ptax).to_timeout
      fonte_responde(sgs.call(1), [{ data: '09/11/2026', valor: '5.5146' }])
      fonte_responde(sgs.call(10_813), [{ data: '09/11/2026', valor: '5.5140' }])

      expect(executar_pronta(ferramenta, 'consulta' => 'dolar')['dados'])
        .to include('compra' => 5.514, 'venda' => 5.5146, 'data' => '2026-11-09')
    end

    it 'Focus: a mediana do ano e do seguinte; sem reserva, com a fonte fora e "nao consegui"' do
      focus = %r{\Ahttps://olinda\.bcb\.gov\.br/olinda/servico/Expectativas/}
      stub_request(:get, focus).to_return(status: 200, headers: { 'Content-Type' => 'application/json' },
                                          body: { value: [{ Indicador: 'IPCA', Data: '2026-11-06', DataReferencia: '2026', Mediana: 5.2195 },
                                                          { Indicador: 'IPCA', Data: '2026-11-06', DataReferencia: '2027', Mediana: 4.9 },
                                                          { Indicador: 'IPCA', Data: '2026-10-30', DataReferencia: '2026', Mediana: 5.3 }] }.to_json)

      dados = executar_pronta(ferramenta, 'consulta' => 'focus', 'indicador' => 'ipca')['dados']
      expect(dados['expectativas']).to eq([{ 'ano' => 2026, 'mediana' => 5.2195, 'data_do_boletim' => '2026-11-06' },
                                           { 'ano' => 2027, 'mediana' => 4.9, 'data_do_boletim' => '2026-11-06' }])
      expect(a_request(:get, focus).with { |pedido| CGI.unescape(pedido.uri.query).include?("Indicador eq 'IPCA'") }).to have_been_made

      stub_request(:get, focus).to_return(status: 500)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'focus', 'indicador' => 'cambio'))).to be(true)
    end

    it 'IPCA: o mes e os 12 meses' do
      fonte_responde(sgs.call(433), [{ data: '01/09/2026', valor: '0.82' }])
      fonte_responde(sgs.call(13_522), [{ data: '01/09/2026', valor: '4.58' }])

      expect(executar_pronta(ferramenta, 'consulta' => 'ipca')['dados'])
        .to include('mes_de_referencia' => '09/2026', 'variacao_no_mes' => 0.82, 'acumulado_12_meses' => 4.58)
    end
  end

  describe 'Cidades e estados (IBGE, reserva BrasilAPI)' do
    let(:ferramenta) { incluir_pronta('cidades', conta: account, agente: agent) }
    let(:ibge) { 'https://servicodados.ibge.gov.br/api/v1/localidades/estados/AC/municipios' }
    let(:brasilapi) { 'https://brasilapi.com.br/api/ibge/municipios/v1/AC?providers=dados-abertos-br,gov' }
    let(:municipios) { %w[Xapuri Acrelândia Tarauacá].map { |nome| { id: 1, nome: nome } } }

    it '"Quais cidades tem no Acre?": a lista do IBGE, em ordem, com o total (o IBGE manda gzip)' do
      corpo = ActiveSupport::Gzip.compress(municipios.to_json)
      cabecalhos = { 'Content-Type' => 'application/json; charset=utf-8', 'Content-Encoding' => 'gzip' }
      stub_request(:get, ibge).to_return(status: 200, body: corpo, headers: cabecalhos)

      dados = executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'AC')['dados']

      expect(dados).to eq('uf' => 'AC', 'estado' => 'Acre', 'total' => 3, 'cidades' => %w[Acrelândia Tarauacá Xapuri])
    end

    it 'a busca pelo nome filtra sem acento e sem caixa; nada achado e "nao encontrado"' do
      fonte_responde(ibge, municipios)

      expect(executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'ac', 'busca' => 'tarauaca')['dados']['cidades']).to eq(['Tarauacá'])
      expect(executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'ac', 'busca' => 'Campinas')['situacao']).to eq('nao_encontrado')
    end

    it 'com o IBGE fora, a BrasilAPI responde; com as duas fora, "nao consegui"' do
      fonte_fora(ibge)
      fonte_responde(brasilapi, [{ nome: 'XAPURI', codigo_ibge: '1200708' }])

      expect(executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'ac')['dados']['cidades']).to eq(['XAPURI'])

      fonte_fora(brasilapi)
      expect(nao_consegui?(executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'ac'))).to be(true)
    end

    it 'estado fora da lista e pedido invalido' do
      expect(executar_pronta(ferramenta, 'consulta' => 'cidades', 'uf' => 'XX')['campo']).to eq('uf')
    end
  end

  describe 'DDD (BrasilAPI, reserva o plano de numeracao)' do
    let(:ferramenta) { incluir_pronta('ddd', conta: account, agente: agent) }
    let(:brasilapi) { 'https://brasilapi.com.br/api/ddd/v1/31' }

    it '"Meu telefone e 31...": Minas Gerais e as cidades do DDD' do
      fonte_responde(brasilapi, { state: 'MG', cities: ['SETE LAGOAS', 'BELO HORIZONTE'] })

      expect(executar_pronta(ferramenta, 'ddd' => '31')['dados'])
        .to eq('ddd' => '31', 'uf' => 'MG', 'estado' => 'Minas Gerais', 'total' => 2, 'cidades' => ['BELO HORIZONTE', 'SETE LAGOAS'])
    end

    it 'com a BrasilAPI fora, o plano diz o estado e avisa que as cidades nao vieram' do
      fonte_lenta(brasilapi)

      expect(executar_pronta(ferramenta, 'ddd' => '(31)')['dados']).to include('uf' => 'MG', 'observacao' => include('Só o estado'))
    end

    it 'DDD que nao existe e pedido invalido, sem chamada' do
      expect(executar_pronta(ferramenta, 'ddd' => '20')).to include('situacao' => 'pedido_invalido', 'campo' => 'ddd')
      expect(a_request(:get, /brasilapi/)).not_to have_been_made
    end
  end

  describe 'Localizacao vira cidade (Photon, reserva Nominatim)' do
    let(:ferramenta) { incluir_pronta('localizacao', conta: account, agente: agent) }
    let(:photon) { %r{\Ahttps://photon\.komoot\.io/reverse} }
    let(:nominatim) { %r{\Ahttps://nominatim\.openstreetmap\.org/reverse} }
    let(:do_photon) { { features: [{ properties: { city: 'Campinas', state: 'São Paulo', countrycode: 'BR' } }] } }
    let(:do_nominatim) { { 'address' => { 'municipality' => 'Campinas', 'ISO3166-2-lvl4' => 'BR-SP', 'country_code' => 'br' } } }

    it 'manda a coordenada arredondada e responde cidade e estado, com a atribuicao do OpenStreetMap' do
      stub_request(:get, photon).to_return(status: 200, body: do_photon.to_json, headers: { 'Content-Type' => 'application/json' })

      dados = executar_pronta(ferramenta, 'latitude' => -22.905612, 'longitude' => -47.060831)['dados']

      expect(dados).to include('cidade' => 'Campinas', 'uf' => 'SP', 'estado' => 'São Paulo', 'fonte_dos_dados' => include('OpenStreetMap'))
      expect(a_request(:get, 'https://photon.komoot.io/reverse?lat=-22.906&lon=-47.061&lang=default&limit=1')).to have_been_made
    end

    it 'com o Photon fora, o Nominatim responde; fora do Brasil e "nao encontrado"' do
      stub_request(:get, photon).to_return(status: 503)
      stub_request(:get, nominatim).to_return(status: 200, body: do_nominatim.to_json, headers: { 'Content-Type' => 'application/json' })

      expect(executar_pronta(ferramenta, 'latitude' => '-22.9', 'longitude' => '-47.06')['dados']).to include('cidade' => 'Campinas', 'uf' => 'SP')

      zerar_tetos_das_prontas # o Nominatim aceita 1 pedido por segundo, e o relógio do exemplo está parado
      fora = { features: [{ properties: { city: 'Lisboa', state: 'Lisboa', countrycode: 'PT' } }] }
      stub_request(:get, photon).to_return(status: 200, body: fora.to_json, headers: { 'Content-Type' => 'application/json' })
      stub_request(:get, nominatim).to_return(status: 200, body: { address: { city: 'Lisboa', country_code: 'pt' } }.to_json,
                                              headers: { 'Content-Type' => 'application/json' })
      expect(executar_pronta(ferramenta, 'latitude' => 38.7, 'longitude' => -9.1)['situacao']).to eq('nao_encontrado')
    end

    it 'coordenada fora da faixa e pedido invalido' do
      expect(executar_pronta(ferramenta, 'latitude' => 120, 'longitude' => -47)['campo']).to eq('latitude')
    end
  end

  describe 'Bancos (BrasilAPI, reserva a lista do STR do Banco Central)' do
    let(:ferramenta) { incluir_pronta('bancos', conta: account, agente: agent) }
    let(:brasilapi) { 'https://brasilapi.com.br/api/banks/v1/341' }
    let(:str) { 'https://www.bcb.gov.br/content/estabilidadefinanceira/str1/ParticipantesSTR.csv' }
    let(:csv) do
      "﻿ISPB,Nome_Reduzido,Número_Código,Participa_da_Compe,Acesso_Principal,Nome_Extenso,Início_da_Operação\n" \
        "00000000,BCO DO BRASIL S.A.,001,Sim,RSFN,Banco do Brasil S.A.,22/04/2002\n" \
        "60701190,ITAÚ UNIBANCO S.A.,341,Sim,RSFN,ITAÚ UNIBANCO S.A.,22/04/2002\n"
    end

    it '"Qual banco e o 341?": Itau Unibanco' do
      fonte_responde(brasilapi, { ispb: '60701190', name: 'ITAÚ UNIBANCO S.A.', code: 341, fullName: 'ITAÚ UNIBANCO S.A.' })

      expect(executar_pronta(ferramenta, 'codigo' => '341')['dados']).to include('codigo' => '341', 'nome' => 'ITAÚ UNIBANCO S.A.')
    end

    it 'com a BrasilAPI fora, o CSV do STR responde (e o 1 vira 001)' do
      fonte_fora('https://brasilapi.com.br/api/banks/v1/1')
      fonte_responde(str, csv, tipo: 'application/octet-stream')

      expect(executar_pronta(ferramenta, 'codigo' => 1)['dados']).to include('codigo' => '001', 'nome' => 'BCO DO BRASIL S.A.')
    end

    it 'codigo que nenhuma das duas tem e "nao encontrado"; as duas fora, "nao consegui"' do
      fonte_fora('https://brasilapi.com.br/api/banks/v1/999', status: 404)
      fonte_responde(str, csv, tipo: 'application/octet-stream')
      expect(executar_pronta(ferramenta, 'codigo' => '999')['situacao']).to eq('nao_encontrado')

      fonte_fora(brasilapi)
      fonte_fora(str)
      expect(nao_consegui?(executar_pronta(ferramenta, 'codigo' => '341'))).to be(true)
    end
  end
end

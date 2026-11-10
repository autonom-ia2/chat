require 'rails_helper'

# #2858 (F1): o teto global por provedor (a cota das APIs públicas é por IP, e todas as contas saem do mesmo IP), com a
# fatia de cada conta, o provedor desligado pela configuração e a resposta em gzip aberta com teto.
RSpec.describe Autonomia::FerramentasProntas::TetoDoProvedor do
  let(:account) { create(:account) }
  let(:outra) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:ibge) { 'https://servicodados.ibge.gov.br/api/v1/localidades/estados?orderBy=nome' }
  let(:estados) { [{ sigla: 'AC', nome: 'Acre', regiao: { nome: 'Norte' } }] }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    ligar_consultas(outra)
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00:00')) { example.run } }

  it 'cada conta usa ate a fatia (25%) do teto do host; a outra conta segue' do
    15.times { expect(described_class.reservar!('photon.komoot.io', conta: account.id)).to be(true) }

    expect(described_class.reservar!('photon.komoot.io', conta: account.id)).to be(false)
    expect(described_class.reservar!('photon.komoot.io', conta: outra.id)).to be(true)
    expect(described_class.reservar!('photon.komoot.io', conta: account.id, agora: Time.now.to_i + 60)).to be(true)
  end

  it 'o teto global soma todas as contas' do
    60.times { |vez| expect(described_class.reservar!('photon.komoot.io', conta: 1000 + vez)).to be(true) }

    expect(described_class.reservar!('photon.komoot.io', conta: account.id)).to be(false)
  end

  it 'o teto diario da parallelum (500 sem chave) fica abaixo do termo, e a fatia de uma conta e 112' do
    expect(described_class.tetos('parallelum.com.br')).to eq([[450, 86_400]])
    expect(described_class.fatia(450)).to eq(112)
  end

  it 'com a chave gratuita da parallelum (1.000 por dia), o teto sobe para 900' do
    with_modified_env(AUTONOMIA_PRONTAS_FIPE_TOKEN: 'chave-de-teste') do
      expect(described_class.tetos('parallelum.com.br')).to eq([[900, 86_400]])
    end
    with_modified_env(AUTONOMIA_PRONTAS_FIPE_TOKEN: '') do
      expect(described_class.tetos('parallelum.com.br')).to eq([[450, 86_400]])
    end
  end

  it 'passou do teto: o provedor e pulado sem chamar, com o motivo, e a reserva responde' do
    ferramenta = incluir_pronta('cidades', conta: account, agente: agent)
    fonte_responde(ibge, estados)
    fonte_responde('https://brasilapi.com.br/api/ibge/uf/v1', estados)
    30.times { described_class.reservar!('servicodados.ibge.gov.br', conta: account.id) } # a fatia da conta: 30 de 120

    expect(executar_pronta(ferramenta, 'consulta' => 'estados')['dados']['estados']).to eq([{ 'uf' => 'AC', 'nome' => 'Acre', 'regiao' => 'Norte' }])
    expect(a_request(:get, ibge)).not_to have_been_made
    expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('ibge.teto_do_provedor' => 1)
  end

  it 'host desligado pela configuracao da instalacao ou pelo ambiente nao sai para a rede' do
    ferramenta = incluir_pronta('cidades', conta: account, agente: agent)
    fonte_responde(ibge, estados)
    fonte_responde('https://brasilapi.com.br/api/ibge/uf/v1', estados)
    InstallationConfig.create!(name: described_class::DESLIGADOS, value: 'ServicoDados.IBGE.gov.br, outro.exemplo')
    GlobalConfig.clear_cache(described_class::DESLIGADOS)

    executar_pronta(ferramenta, 'consulta' => 'estados')

    expect(a_request(:get, ibge)).not_to have_been_made
    expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('ibge.provedor_desligado' => 1)

    InstallationConfig.find_by(name: described_class::DESLIGADOS).destroy!
    GlobalConfig.clear_cache(described_class::DESLIGADOS)
    with_modified_env(AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS: 'brasilapi.com.br') do
      expect(described_class.desligado?('brasilapi.com.br')).to be(true)
      expect(described_class.desligado?('servicodados.ibge.gov.br')).to be(false)
    end
  end

  it 'Redis fora: o teto e a configuracao deixam o pedido seguir, e a consulta responde' do
    ferramenta = incluir_pronta('cidades', conta: account, agente: agent)
    fonte_responde(ibge, estados)
    allow(Redis::Alfred).to receive(:with).and_raise(Redis::CannotConnectError)
    allow(GlobalConfig).to receive(:get).and_raise(Redis::CannotConnectError)

    expect(executar_pronta(ferramenta, 'consulta' => 'estados')['situacao']).to eq('encontrado')
  end

  it 'defeito nosso no teto nao vira "sem Redis": sobe e vai ao rastreador como defeito' do
    ferramenta = incluir_pronta('cidades', conta: account, agente: agent)
    allow(Redis::Alfred).to receive(:with).and_raise(NoMethodError)

    expect(executar_pronta(ferramenta, 'consulta' => 'estados')['situacao']).to eq('nao_consegui_consultar')
    expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to eq('defeito' => 1)
  end

  describe 'a resposta em gzip' do
    let(:cliente) do
      prazo_final = Autonomia::FerramentasProntas::ClienteHttp.agora + 5
      Autonomia::FerramentasProntas::ClienteHttp.new(hosts: ['servicodados.ibge.gov.br'], prazo_final: prazo_final)
    end
    let(:url) { 'https://servicodados.ibge.gov.br/api/v1/localidades/estados' }

    it 'e aberta quando cabe no teto' do
      stub_request(:get, url).to_return(status: 200, body: ActiveSupport::Gzip.compress('[{"nome":"Acre"}]'),
                                        headers: { 'Content-Type' => 'application/json', 'Content-Encoding' => 'gzip' })

      expect(cliente.get_json('servicodados.ibge.gov.br', '/api/v1/localidades/estados', prazo: 3)).to eq([{ 'nome' => 'Acre' }])
    end

    it 'aberta passando do teto (bomba de gzip) e recusada, sem abrir tudo' do
      bomba = ActiveSupport::Gzip.compress(' ' * 2.megabytes)
      stub_request(:get, url).to_return(status: 200, body: bomba, headers: { 'Content-Type' => 'application/json' })

      expect { cliente.get_json('servicodados.ibge.gov.br', '/api/v1/localidades/estados', prazo: 3, max_bytes: 1.megabyte) }
        .to raise_error(Autonomia::FerramentasProntas::Provedor::Falha, 'resposta_grande_demais')
    end

    it 'gzip corrompido e resposta invalida' do
      stub_request(:get, url).to_return(status: 200, body: "\x1F\x8B\x08quebrado".b, headers: { 'Content-Type' => 'application/json' })

      expect { cliente.get_json('servicodados.ibge.gov.br', '/api/v1/localidades/estados', prazo: 3) }
        .to raise_error(Autonomia::FerramentasProntas::Provedor::Falha, 'resposta_invalida')
    end
  end
end

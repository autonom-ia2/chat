require 'rails_helper'

# #2858 (F1): o teto global por provedor (a cota das APIs públicas é por IP, e todas as contas saem do mesmo IP), o
# provedor desligado pela configuração (o Nominatim exige poder parar sem atualizar o software) e a resposta em gzip
# aberta com teto.
RSpec.describe Autonomia::FerramentasProntas::TetoDoProvedor do
  let(:account) { create(:account) }
  let(:outra) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:agente_da_outra) do
    Autonomia::Agents::Agent.create!(account: outra, name: 'Bot', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:photon) { %r{\Ahttps://photon\.komoot\.io/reverse} }
  let(:nominatim) { %r{\Ahttps://nominatim\.openstreetmap\.org/reverse} }
  let(:do_nominatim) { { 'address' => { 'municipality' => 'Campinas', 'ISO3166-2-lvl4' => 'BR-SP', 'country_code' => 'br' } }.to_json }

  before do
    resolver_hosts_das_prontas
    ligar_consultas(account)
    ligar_consultas(outra)
  end

  around { |example| travel_to(Time.zone.parse('2026-11-10 10:00:00')) { example.run } }

  it 'conta por host e por janela, somando todas as contas' do
    expect(described_class.reservar!('nominatim.openstreetmap.org')).to be(true)
    expect(described_class.reservar!('nominatim.openstreetmap.org')).to be(false)
    expect(described_class.reservar!('photon.komoot.io')).to be(true)
    expect(described_class.reservar!('nominatim.openstreetmap.org', agora: Time.now.to_i + 1)).to be(true)
  end

  it 'o teto diario da parallelum (500 sem chave) fica abaixo do termo' do
    expect(described_class.tetos('parallelum.com.br')).to eq([[450, 86_400]])
  end

  it 'passou do teto: o provedor e pulado sem chamar, com o motivo, e a reserva responde' do
    stub_request(:get, photon).to_return(status: 503)
    stub_request(:get, nominatim).to_return(status: 200, body: do_nominatim, headers: { 'Content-Type' => 'application/json' })
    da_conta = incluir_pronta('localizacao', conta: account, agente: agent)
    da_outra = incluir_pronta('localizacao', conta: outra, agente: agente_da_outra)

    expect(executar_pronta(da_conta, 'latitude' => -22.9, 'longitude' => -47.06)['dados']['cidade']).to eq('Campinas')
    saida = executar_pronta(da_outra, 'latitude' => -23.5, 'longitude' => -46.6)

    expect(saida['situacao']).to eq('nao_consegui_consultar')
    expect(a_request(:get, nominatim)).to have_been_made.once
    expect(Autonomia::FerramentasProntas::Uso.find_by(account_id: outra.id).motivos)
      .to eq('photon.erro_da_fonte' => 1, 'nominatim.teto_do_provedor' => 1)
  end

  it 'host desligado pela configuracao nao sai para a rede' do
    stub_request(:get, photon).to_return(status: 503)
    stub_request(:get, nominatim).to_return(status: 200, body: do_nominatim, headers: { 'Content-Type' => 'application/json' })
    ferramenta = incluir_pronta('localizacao', conta: account, agente: agent)

    with_modified_env(AUTONOMIA_PRONTAS_HOSTS_DESLIGADOS: 'Nominatim.OpenStreetMap.org, outro.exemplo') do
      expect(executar_pronta(ferramenta, 'latitude' => -22.9, 'longitude' => -47.06)['situacao']).to eq('nao_consegui_consultar')
    end

    expect(a_request(:get, nominatim)).not_to have_been_made
    expect(Autonomia::FerramentasProntas::Uso.sole.motivos).to include('nominatim.provedor_desligado' => 1)
  end

  it 'Redis fora: o pedido segue (o teto protege a cota, nao o dado)' do
    allow(Redis::Alfred).to receive(:with).and_raise(Redis::CannotConnectError)

    expect(described_class.reservar!('photon.komoot.io')).to be(true)
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

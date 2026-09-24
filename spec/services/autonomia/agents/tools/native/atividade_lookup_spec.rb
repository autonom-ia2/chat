require 'rails_helper'

# A BUSCA DE ATIVIDADE do especialista de empresarial (chat#641). O texto que o MODELO recebe é afirmado inteiro:
# é ele que ensina a escolher uma opção por seguradora, a perguntar térreo ou andar e a deixar de fora a seguradora
# sem opção segura. E a falha técnica nunca vira atividade inventada.
RSpec.describe Autonomia::Agents::Tools::Native::AtividadeLookup do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bot', agent_type: 'custom',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:connector) { Autonomia::Insurance::Connector.client }

  before do
    enable_test_encryption!
    allow(Autonomia::Insurance::Connector).to receive(:client).and_return(connector)
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  def ready_connection
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: 'ready')
    record.store_session!({ 'multicalculoToken' => 'multi' }, expires_at: 3.hours.from_now)
    record
  end

  def buscar(termos)
    described_class.new(agent: agent, params: { 'termos' => termos }).call
  end

  it 'e sincrona, esta no catalogo, e so aparece com conexao pronta' do
    expect(described_class.async?).to be(false)
    expect(Autonomia::Agents::Tools::Registry.find('buscar_atividade')).to eq(described_class)
    expect(described_class.available_for?(agent)).to be(false)
    ready_connection
    expect(described_class.available_for?(agent)).to be(true)
  end

  it 'declara termos como lista de texto, que o modo strict aceita' do
    esquema = described_class.openai_schema(agent)[:parameters]

    expect(esquema[:properties]['termos']).to include('type' => 'array', 'items' => { 'type' => 'string' })
    expect(esquema[:required]).to eq(['termos'])
  end

  describe 'com opcoes' do
    it 'lista uma linha por opcao, so as seguradoras com opcao, e ensina a escolher' do
      ready_connection

      texto = buscar(%w[escritorio])

      expect(texto).to eq(
        "Termo \"escritorio\":\n" \
        "- Porto Seguro (seguradora 8): key 484, value ESCRITORIO - TERREO/SOBRADO\n" \
        "- Porto Seguro (seguradora 8): key 487, value ESCRITORIO - A PARTIR DO PRIMEIRO ANDAR\n" \
        "- Hdi (seguradora 4): key 700160, value ESCRITORIO\n\n#{described_class::COMO_ESCOLHER}"
      )
      expect(texto).not_to include('Zurich')
    end

    it 'o que ensina: a mesma atividade, terreo ou andar, outro termo, e nunca atividade diferente' do
      expect(described_class::COMO_ESCOLHER).to include(
        'a mesma atividade que o cliente contou', 'pergunte uma vez se é térreo ou andar',
        'busque de novo com outro termo', 'deixe essa seguradora de fora',
        'Nunca escolha uma atividade diferente da do cliente'
      )
    end

    it 'limpa e deduplica os termos antes de ir ao conector' do
      ready_connection
      allow(connector).to receive(:atividade_lookup).and_call_original

      buscar([' padaria ', 'padaria', '', 'confeitaria'])

      expect(connector).to have_received(:atividade_lookup)
        .with(provider: 'agger', session: hash_including('multicalculoToken' => 'multi'), product: 'empresarial',
              termos: %w[padaria confeitaria])
    end
  end

  it 'nenhuma seguradora com opcao: busca de novo, e depois encaminha, sem perguntar em laco' do
    ready_connection
    allow(connector).to receive(:atividade_lookup)
      .and_return({ 'porTermo' => [{ 'termo' => 'xyz', 'porSeguradora' => [{ 'insurerCode' => '8', 'opcoes' => [] }] }] })

    expect(buscar(%w[xyz])).to eq(described_class::NADA_ACHADO)
    expect(described_class::NADA_ACHADO)
      .to include('Busque de novo com outro termo', 'não pergunte de novo', 'encaminhar para alguém da equipe')
  end

  describe 'recusas' do
    it 'sem termo nenhum: pede os termos, sem chamar o conector' do
      ready_connection
      allow(connector).to receive(:atividade_lookup)

      expect(buscar(['', ' '])).to eq(described_class::SEM_TERMOS)
      expect(connector).not_to have_received(:atividade_lookup)
    end

    it 'termo curto que o adapter recusa: pede os termos' do
      ready_connection

      expect(buscar(%w[ab])).to eq(described_class::SEM_TERMOS)
    end

    it 'falha tecnica: nao inventa atividade, e o log nao leva o termo' do
      ready_connection
      allow(connector).to receive(:atividade_lookup)
        .and_raise(Autonomia::Insurance::Connector::Error.new(:upstream, 'portal fora'))
      allow(Rails.logger).to receive(:warn)

      expect(buscar(%w[escritorio])).to eq(described_class::INDISPONIVEL)
      expect(Rails.logger).to have_received(:warn).with(a_string_including('busca de atividade falhou'))
      expect(Rails.logger).not_to have_received(:warn).with(a_string_including('escritorio'))
    end

    # Revisão da chat#654, como na consulta de CEP: validation sem perguntas (o 401 do portal com envelope) não é
    # culpa do termo.
    it 'recusa de validacao sem perguntas: indisponivel, e nao pede outro termo' do
      ready_connection
      allow(connector).to receive(:atividade_lookup)
        .and_raise(Autonomia::Insurance::Connector::Error.new(:validation, 'envelope de erro'))

      expect(buscar(%w[escritorio])).to eq(described_class::INDISPONIVEL)
    end

    it 'sessao sem resposta: indisponivel' do
      ready_connection
      allow(connector).to receive(:atividade_lookup).and_return(nil)

      expect(buscar(%w[escritorio])).to eq(described_class::INDISPONIVEL)
    end
  end
end

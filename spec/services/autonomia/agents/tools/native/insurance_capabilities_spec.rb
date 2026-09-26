require 'rails_helper'

RSpec.describe Autonomia::Agents::Tools::Native::InsuranceCapabilities do
  let(:account) { create(:account) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Bot', agent_type: 'custom', status: :active,
      enabled: true, instruction: 'Atenda.'
    )
  end
  let(:capabilities) do
    { 'products' => [
      { 'product' => 'auto', 'enabled' => true,
        'insurers' => [{ 'enabled' => true }, { 'enabled' => true }, { 'enabled' => false }] },
      { 'product' => 'vida_em_grupo', 'enabled' => true, 'insurers' => [{ 'enabled' => true }] },
      { 'product' => 'celular', 'enabled' => false, 'insurers' => [] }
    ] }
  end

  def create_connection(status: 'ready', scan_at: Time.zone.parse('2026-09-04 10:00'))
    enable_test_encryption!
    Autonomia::Insurance::Connection.create!(
      account: account, username: 'c@x.com', password: 'segredo', status: status,
      capabilities: capabilities, last_capability_scan_at: scan_at
    )
  end

  describe '.available_for?' do
    it 'is false when the account has no connection at all' do
      allow(Autonomia::Insurance::Config).to receive(:enabled?).and_return(true)
      expect(described_class.available_for?(agent)).to be(false)
    end

    it 'is false when the quoting module is off for the account' do
      create_connection
      allow(Autonomia::Insurance::Config).to receive(:enabled?).and_return(false)
      expect(described_class.available_for?(agent)).to be(false)
    end

    it 'is false when the connection exists but is not ready' do
      create_connection(status: 'auth_required')
      allow(Autonomia::Insurance::Config).to receive(:enabled?).and_return(true)
      expect(described_class.available_for?(agent)).to be(false)
    end

    it 'is true with the module on and a ready connection' do
      create_connection
      allow(Autonomia::Insurance::Config).to receive(:enabled?).and_return(true)
      expect(described_class.available_for?(agent)).to be(true)
    end
  end

  describe '#call' do
    it 'describes only enabled products, counting only enabled insurers' do
      # Arrange
      create_connection

      # Act
      output = described_class.new(agent: agent).call

      # Assert — celular está desabilitado e não aparece; auto tem 3 seguradoras, 2 habilitadas
      expect(output).to include('Auto (2 seguradoras)')
      expect(output).to include('Vida em grupo (1 seguradoras)')
      expect(output).not_to include('Celular')
      expect(output).to include('Levantamento de 04/09/2026.')
    end

    it 'says plainly that there is no connection yet' do
      expect(described_class.new(agent: agent).call)
        .to eq('A corretora ainda não conectou a conta do AGGER.')
    end

    it 'separates "connected but nothing enabled" from "not connected"' do
      enable_test_encryption!
      Autonomia::Insurance::Connection.create!(
        account: account, username: 'c@x.com', password: 'segredo', status: 'ready',
        capabilities: { 'products' => [{ 'product' => 'auto', 'enabled' => false, 'insurers' => [] }] }
      )

      expect(described_class.new(agent: agent).call)
        .to eq('A conexão está ativa, mas nenhum ramo está habilitado nesta conta do AGGER.')
    end

    it 'returns a named error without echoing the exception message' do
      create_connection
      allow(Autonomia::Insurance::Connection).to receive(:for_account).and_raise('senha=segredo')

      output = described_class.new(agent: agent).call

      expect(output).to eq({ error: 'capabilities_unavailable' }.to_json)
      expect(output).not_to include('segredo')
    end
  end

  it 'declares a parameterless strict schema' do
    schema = described_class.openai_schema
    expect(schema[:name]).to eq('consultar_produtos_cotacao')
    expect(schema[:parameters][:properties]).to eq({})
    expect(schema[:strict]).to be(true)
  end

  # CONVERSA 7150 (26/09/2026): a Lia leu a lista única como "tudo isto eu coto" e ofereceu seguro de vida. No Agente de
  # Cotação a ferramenta separa o que a IA cota na hora do que a corretora trabalha e fica com a equipe.
  describe 'no Agente de Cotação' do
    let(:lia) do
      Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :active,
                                       enabled: true, instruction: 'Atenda.')
    end
    let(:inbox) { create(:inbox, account: account) }
    let(:conversation) { create(:conversation, account: account, inbox: inbox, assignee: nil) }
    let(:turno) do
      Autonomia::Agents::Tools::Delivery.new(conversation: conversation, agent_inbox: nil, origin_message_id: nil)
    end
    let(:recentes) { Autonomia::Agents::Tools::RecusasRecentes }
    let(:capabilities) do
      { 'products' => [
        { 'product' => 'residencial', 'enabled' => true, 'insurers' => [{ 'enabled' => true }] },
        { 'product' => 'auto', 'enabled' => true, 'insurers' => [{ 'enabled' => true }, { 'enabled' => true }] },
        { 'product' => 'vida', 'enabled' => true, 'insurers' => Array.new(8) { { 'enabled' => true } } },
        { 'product' => 'vida_global', 'enabled' => true, 'insurers' => [{ 'enabled' => true }] },
        { 'product' => 'celular', 'enabled' => false, 'insurers' => [] }
      ] }
    end

    before { recentes.retirar(conversation.id) }

    it 'separa o que a IA cota na hora, com as seguradoras, do que fica com a equipe, sem contagem' do
      create_connection

      output = described_class.new(agent: lia).call

      expect(output).to eq('A IA cota na hora, nesta conta: Auto (2 seguradoras). A corretora também trabalha com estes, ' \
                           'que a IA não cota e ficam com a equipe da corretora: Residencial; Vida; Vida global. ' \
                           'Levantamento de 04/09/2026.')
      expect(output).not_to include('8 seguradoras', 'Celular', '—', '`')
    end

    it 'residencial liberado e habilitado passa para a lista do que a IA cota' do
      create_connection
      Autonomia::Insurance::Config.liberar_ramo!(account, 'residencial')

      output = described_class.new(agent: lia).call

      expect(output).to start_with('A IA cota na hora, nesta conta: Residencial (1 seguradoras); Auto (2 seguradoras). ')
      expect(output).to include('ficam com a equipe da corretora: Vida; Vida global.')
    end

    it 'oferece ramo_pedido só com os códigos do que fica com a equipe, anulável, no modo strict' do
      create_connection

      schema = described_class.openai_schema(lia)[:parameters]

      expect(schema[:required]).to eq(['ramo_pedido'])
      expect(schema[:additionalProperties]).to be(false)
      expect(schema[:properties]['ramo_pedido']).to include('type' => %w[string null],
                                                            'enum' => ['residencial', 'vida', 'vida_global', nil])
    end

    it 'anota para a equipe o ramo pedido que está na lista dela; o que a IA cota ou está fora, não' do
      create_connection

      described_class.new(agent: lia, params: { 'ramo_pedido' => 'vida' }, delivery: turno).call
      described_class.new(agent: lia, params: { 'ramo_pedido' => 'auto' }, delivery: turno).call
      described_class.new(agent: lia, params: { 'ramo_pedido' => 'celular' }, delivery: turno).call
      described_class.new(agent: lia, params: { 'ramo_pedido' => nil }, delivery: turno).call

      expect(recentes.retirar(conversation.id)).to eq(['ramo_pedido:vida'])
    end

    # Regressão: a conta que só tem o que a IA cota e o agente comum seguem com a ferramenta sem parâmetro.
    it 'sem ramo que fica com a equipe, e no agente comum, o schema continua sem parâmetro' do
      enable_test_encryption!
      Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo', status: 'ready',
                                               capabilities: { 'products' => [{ 'product' => 'auto', 'enabled' => true }] })

      expect(described_class.openai_schema(lia)[:parameters][:properties]).to eq({})
      expect(described_class.new(agent: lia).call).to eq('A IA cota na hora, nesta conta: Auto.')
      expect(described_class.openai_schema(agent)[:parameters][:properties]).to eq({})
    end

    it 'montar o schema nunca levanta: a falha vira ferramenta sem parâmetro' do
      allow(Autonomia::Insurance::Connection).to receive(:for_account).and_raise('senha=segredo')

      expect(described_class.openai_schema(lia)[:parameters][:properties]).to eq({})
    end
  end
end

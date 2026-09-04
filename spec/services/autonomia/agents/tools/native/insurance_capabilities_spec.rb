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
end

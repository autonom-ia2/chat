require 'rails_helper'

# O FORMULÁRIO DO ESPECIALISTA DE EMPRESARIAL (chat#641). Além dos campos do ramo, que vêm do schema do adapter como em
# residencial, ele tem a ATIVIDADE ESCOLHIDA EM CADA SEGURADORA: uma lista de objetos, fora de `configuracoes`, que o
# adapter lê no topo da entrada. O que se prova:
#   o especialista de empresarial vê os campos do ramo e a lista de atividades; os de auto e residencial, não;
#   a lista passa no modo strict da OpenAI, com o item como objeto fechado;
#   a atividade escolhida chega à entrada da cotação, e a escolha incompleta fica de fora.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) { create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true }) }
  let(:lia) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote',
                                     status: :active, enabled: true, instruction: 'Atenda.')
  end
  let(:mock) { Autonomia::Insurance::Connector::Mock }
  let(:schemas_guardados) do
    { 'auto' => mock::SCHEMA_AUTO, 'residencial' => mock::SCHEMA_RESIDENCIAL, 'empresarial' => mock::SCHEMA_EMPRESARIAL }
  end

  around do |example|
    with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run }
  end

  before do
    enable_test_encryption!
    Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
                                    .update!(status: 'ready', metadata: { 'quote_schemas' => schemas_guardados })
    allow(Autonomia::Insurance::Connector).to receive(:client).and_raise('não deveria chamar o adapter')
  end

  def especialista(slug)
    Autonomia::Agents::Specialist.create!(agent: lia, account: account, slug: slug, name: slug,
                                          description: 'cota', instruction: 'Cote.')
  end

  def nomes(slug)
    described_class.params_for(lia, especialista: especialista(slug)).pluck('name')
  end

  it 'o de empresarial vê os campos do ramo e a atividade por seguradora; os outros, não' do
    expect(nomes('cotacao_empresarial')).to eq(described_class.params.pluck('name') - ['dados'] +
                                                 %w[segurado configuracoes atividades])
    expect(nomes('cotacao_residencial')).not_to include('atividades')
    expect(described_class.params_for(lia).pluck('name')).not_to include('atividades')
  end

  it 'a lista de atividades passa no modo strict, com o item como objeto fechado' do
    schema = described_class.openai_schema(lia, especialista: especialista('cotacao_empresarial'))[:parameters]
    atividades = schema[:properties]['atividades']
    item = atividades['items']

    expect(schema[:required]).to include('atividades')
    expect(atividades['type']).to eq('array')
    expect(item[:properties].keys).to eq(%w[seguradora key value])
    expect(item[:required]).to match_array(item[:properties].keys)
    expect(item[:additionalProperties]).to be(false)
  end

  describe 'a entrada da cotação' do
    def entrada(atividades)
      Autonomia::Insurance::QuoteInput.new(
        produto: 'empresarial', dados: {}, commission_percent: 10.0, grupos_do_ramo: %w[segurado configuracoes],
        params: { 'cpf' => '11222333000181', 'configuracoes' => { 'imovelNumero' => '1540' }, 'atividades' => atividades }
      ).to_h
    end

    it 'leva a atividade escolhida em cada seguradora, no topo, como o adapter lê' do
      montada = entrada([{ 'seguradora' => '8', 'key' => '484', 'value' => 'ESCRITORIO - TERREO' },
                         { 'seguradora' => 4, 'key' => 700_160, 'value' => ' ESCRITORIO ' }])

      expect(montada['atividades']).to eq([{ 'seguradora' => '8', 'key' => '484', 'value' => 'ESCRITORIO - TERREO' },
                                           { 'seguradora' => '4', 'key' => '700160', 'value' => 'ESCRITORIO' }])
      expect(montada.dig('configuracoes', 'imovelNumero')).to eq('1540')
    end

    it 'a escolha incompleta fica de fora, e sem nenhuma a chave não vai' do
      montada = entrada([{ 'seguradora' => '8', 'key' => '484', 'value' => nil }, { 'seguradora' => '4' }])

      expect(montada).not_to have_key('atividades')
      expect(entrada(nil)).not_to have_key('atividades')
    end
  end
end

require 'rails_helper'

# #3211 (Tarefa 9): as prontas do agente contratado vêm do catálogo; o "Incluir" da vitrine recusa, só o "Contratar" passa.
RSpec.describe Autonomia::FerramentasProntas::Incluir do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end
  let(:contratado) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca })
  end

  before do
    enable_test_encryption!
    ligar_prontas(account)
  end

  it 'no agente contratado recusa com agente_contratado fora do Contratar' do
    expect { described_class.new(account: account, agent: contratado, fonte: 'cep').call }
      .to raise_error(described_class::Recusado) { |erro| expect(erro.motivo).to eq('agente_contratado') }
    expect(contratado.tools.count).to eq(0)
  end

  it 'no agente contratado cria a ferramenta com pelo_contratar: true' do
    resultado = described_class.new(account: account, agent: contratado, fonte: 'cep', pelo_contratar: true).call

    expect(resultado.ferramenta).to have_attributes(fonte_pronta: 'cep', slug: 'pronta_cep')
  end
end

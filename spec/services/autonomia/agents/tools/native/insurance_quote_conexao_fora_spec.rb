require 'rails_helper'

# CONEXÃO FORA, COTAÇÃO RECUSADA NA HORA (chat#585). Em 21/09/2026 às 18:30 o portal recusou o login da corretora
# ("Sessões lotadas") e a conexão da conta 16 ficou offline por nove horas. A cotação pedida nesse intervalo foi
# ACEITA — o especialista disse que ia cotar — e morreu depois de 23 tentativas e sete minutos, sem chance nenhuma
# de dar certo. Sem conexão pronta, a conferência recusa antes: nada é aberto, e o modelo sabe por quê.
RSpec.describe Autonomia::Agents::Tools::Native::InsuranceQuote do
  let(:account) do
    create(:account, internal_attributes: { 'autonomia_insurance_enabled' => true, 'autonomia_agents_enabled' => true })
  end
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active,
                                     enabled: true, instruction: 'Atenda.')
  end
  let(:params) { { 'produto' => 'auto', 'vehicle' => { 'plate' => 'ABC1D23' }, 'cpf' => '04297912678', 'cep' => '31110-210' } }

  around { |example| with_modified_env(INSURANCE_QUOTING_ENABLED: 'true') { example.run } }

  def conexao(status)
    enable_test_encryption!
    record = Autonomia::Insurance::Connection.create!(account: account, username: 'c@x.com', password: 'segredo')
    record.update!(status: status, metadata: { 'quote_schemas' => { 'auto' => Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO } })
  end

  it 'conexão offline: recusa na conferência, com o motivo nomeado' do
    conexao('offline')

    conferencia = described_class.new(agent: agent, params: params).precheck

    expect(conferencia.motivo).to eq('conexao_indisponivel')
    expect(conferencia.to_s).to include('não foi aberta')
  end

  it 'sem conexão nenhuma, também' do
    expect(described_class.new(agent: agent, params: params).precheck.motivo).to eq('conexao_indisponivel')
  end

  it 'o motivo está no catálogo do registro de recusa' do
    expect(Autonomia::Agents::Tools::Recusa::MOTIVOS).to have_key('conexao_indisponivel')
  end
end

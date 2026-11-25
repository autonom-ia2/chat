require 'rails_helper'

# O AGENTE CONTRATADO DO CATÁLOGO (#3211) no model: a marca, a instrução e as ferramentas do catálogo, o tipo fixo, o
# acesso à seguradora conferido para atender e a marca protegida do save com cópia velha.
RSpec.describe Autonomia::Agents::Contratado do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Corretora de seguros desde 2010.' }
  end

  before { enable_test_encryption! }

  def build_agent(config:)
    Autonomia::Agents::Agent.new(account: account, name: 'Bia', agent_type: 'sdr', config: config)
  end

  def criar_contratado(config_extra: {})
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'sdr', instruction: 'retrato do nascimento',
                                     config: { 'contratado' => marca }.merge(config_extra))
  end

  it 'é contratado só com a marca de um modelo do catálogo' do
    expect(build_agent(config: { 'contratado' => marca }).contratado?).to be(true)
    expect(build_agent(config: { 'contratado' => marca.merge('modelo' => 'outro') }).contratado?).to be(false)
    expect(build_agent(config: {}).contratado?).to be(false)
  end

  it 'instrução mantida: recusa refresh, rollback, Construtor e modo manual' do
    agente = criar_contratado
    expect { agente.refresh_instruction!('x', expected_instruction: agente.instruction) }
      .to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
    expect { agente.apply_builder_config!('t', { instruction: 'x' }) }.to raise_error(Autonomia::Agents::Agent::InstrucaoMantida)
    agente.mode = :manual
    expect(agente).not_to be_valid
  end

  it 'o prompt é o arquivo renderizado, não a coluna' do
    agente = criar_contratado
    agente.update_columns(instruction: 'velha') # rubocop:disable Rails/SkipsModelValidations
    expect(agente.instrucao_do_sistema).to include('Você é Bia, da Corretora Exemplo')
  end

  it 'ferramentas fixas do catálogo, mesmo com native_tool_slugs gravado' do
    agente = criar_contratado(config_extra: { 'native_tool_slugs' => %w[agendar_reuniao] })
    expect(agente.ferramentas_nativas).to eq(%w[cotar_seguro_viagem detalhes_da_cotacao gerar_proposta_seguro_viagem])
  end

  it 'o tipo não muda depois de contratado' do
    agente = criar_contratado
    agente.agent_type = 'custom'
    expect(agente).not_to be_valid
    expect(agente.errors[:agent_type]).to be_present
  end

  it 'não passa a atender sem acesso ok' do
    agente = criar_contratado
    # Caixa arranjada: com vínculo ativo, `tem_onde_trabalhar?` é verdade e a única regra que falha é a do acesso (R11).
    inbox = create(:inbox, account: agente.account)
    Autonomia::Agents::AgentInbox.create!(agent: agente, inbox: inbox, account: agente.account,
                                          agent_bot: create(:agent_bot, account: agente.account))
    agente.assign_attributes(status: :active, enabled: true)
    expect(agente.valid?(:ativacao)).to be(false)
    expect(agente.errors[:base]).to eq([I18n.t('autonomia.contratados.acesso_pendente')])
    agente.create_acesso_da_seguradora!(account: agente.account, login: 'corretor.teste', senha: 'x', estado: 'ok')
    expect(agente.valid?(:ativacao)).to be(true)
  end

  it 'save comum com cópia velha não desfaz a edição dos três campos' do
    agente = criar_contratado
    velho = Autonomia::Agents::Agent.find(agente.id)
    agente.update!(config: agente.config.merge('contratado' => marca.merge('nome_corretora' => 'Nova')))
    velho.update!(config: velho.config.merge('greeting_extra' => 'x'))
    expect(agente.reload.config['contratado']['nome_corretora']).to eq('Nova')
  end

  it 'save comum com cópia velha não volta a versão da base gravada por fora do save' do
    agente = criar_contratado
    velho = Autonomia::Agents::Agent.find(agente.id)
    Autonomia::Agents::Agent.where(id: agente.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ['config = jsonb_set(config, \'{contratado_base_versao}\', ?::jsonb, true)', 'v2'.to_json]
    )
    velho.update!(config: velho.config.merge('greeting_extra' => 'x'))
    expect(agente.reload.config).to include('contratado_base_versao' => 'v2', 'greeting_extra' => 'x')
  end
end

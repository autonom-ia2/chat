require 'rails_helper'

RSpec.describe Autonomia::Agents::Contratados::BaseEmDiaJob do
  let(:account) { create(:account) }
  let(:marca) do
    { 'modelo' => 'seguro_viagem_universal', 'nome_agente' => 'Bia', 'nome_corretora' => 'Corretora Exemplo',
      'sobre_corretora' => 'Desde 2010.' }
  end
  let(:semear) { Autonomia::Agents::Contratados::SemearBaseJob }

  before do
    enable_test_encryption!
    # A chave da conta é de mentira: a validação do gancho não chama o provedor.
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    ligar(account)
  end

  def ligar(conta, chave: true)
    conta.enable_features!('agente_seguro_viagem_universal', 'agente_ferramentas_prontas',
                           'agente_ferramentas_prontas_consultas')
    return unless chave

    create(:integrations_hook, account: conta, app_id: 'crm_kanban_ai', hook_type: :account,
                               settings: { 'api_key' => 'chave-da-conta-teste' })
  end

  def contratado(versao, conta: account)
    config = { 'contratado' => marca }
    config['contratado_base_versao'] = versao if versao
    Autonomia::Agents::Agent.create!(account: conta, name: 'Bia', agent_type: 'sdr', instruction: 'retrato', config: config)
  end

  it 'enfileira só os contratados com a base de outra versão (ou nunca semeada)' do
    velho = contratado('0000000000000000')
    nunca = contratado(nil)
    em_dia = contratado(Autonomia::Agents::Contratados::Base::VERSAO)
    apagado = contratado(nil)
    apagado.update_columns(deleted_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    comum = Autonomia::Agents::Agent.create!(account: account, name: 'Ana', agent_type: 'sdr')

    expect { described_class.perform_now }.to have_enqueued_job(semear).exactly(2)
    expect(semear).to have_been_enqueued.with(velho.id)
    expect(semear).to have_been_enqueued.with(nunca.id)
    [em_dia, apagado, comum].each { |fora| expect(semear).not_to have_been_enqueued.with(fora.id) }
  end

  it 'deixa de fora, em silêncio, a conta sem a própria chave e a conta com o modelo desligado' do
    com_chave = contratado(nil)
    sem_chave = create(:account).tap { |conta| ligar(conta, chave: false) }
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-da-instalacao-teste')
    desligada = create(:account).tap { |conta| ligar(conta) }
    desligada.disable_features!('agente_seguro_viagem_universal')
    de_fora = [contratado(nil, conta: sem_chave), contratado(nil, conta: desligada)]
    allow(Rails.logger).to receive(:warn)

    expect { described_class.perform_now }.to have_enqueued_job(semear).exactly(1)
    expect(semear).to have_been_enqueued.with(com_chave.id)
    de_fora.each { |fora| expect(semear).not_to have_been_enqueued.with(fora.id) }
    expect(Rails.logger).not_to have_received(:warn)
  end

  it 'está no cron de hora em hora' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))
    expect(agenda['autonomia_contratados_base_em_dia_job']).to eq(
      'cron' => '17 * * * *', 'class' => described_class.name, 'queue' => 'scheduled_jobs'
    )
  end
end

require 'rails_helper'
# O processo do worker carrega o capsule sozinho; o do teste, não.
require 'sidekiq/capsule'

# #1430: a fila própria das ferramentas HTTP assíncronas. Isola uma conta com ferramenta lenta das filas de todo mundo
# (proteção contra defeito, não teto de uso). O capsule e o pool do banco leem o MESMO número.
RSpec.describe AgentToolsQueue do
  it 'o capsule pega so a fila agent_tools, com a concorrencia do ENV' do
    with_modified_env(AGENT_TOOLS_CONCURRENCY: '7') do
      config = Sidekiq::Config.new
      described_class.configurar(config)

      capsule = config.capsules.fetch('agent_tools')
      expect(capsule.queues).to eq(['agent_tools'])
      expect(capsule.concurrency).to eq(7)
    end
  end

  it 'sem o ENV a concorrencia e o padrao' do
    with_modified_env(AGENT_TOOLS_CONCURRENCY: nil) do
      expect(described_class.concorrencia).to eq(10)
    end
  end

  it 'ENV que nao e inteiro nao derruba o boot: cai no padrao e avisa' do
    with_modified_env(AGENT_TOOLS_CONCURRENCY: 'dez', SIDEKIQ_CONCURRENCY: '3O') do
      expect { expect(described_class.pool_do_sidekiq).to eq(20) }.to output(a_string_including('AGENT_TOOLS_CONCURRENCY')).to_stderr
    end
  end

  it 'o pool do worker soma as threads do processo principal e as do capsule' do
    with_modified_env(SIDEKIQ_CONCURRENCY: '30', AGENT_TOOLS_CONCURRENCY: nil) do
      expect(described_class.pool_do_sidekiq).to eq(40)
    end
    with_modified_env(SIDEKIQ_CONCURRENCY: nil, AGENT_TOOLS_CONCURRENCY: '4') do
      expect(described_class.pool_do_sidekiq).to eq(14)
    end
  end

  it 'o database.yml usa o pool do worker no Sidekiq' do
    expect(Rails.root.join('config/database.yml').read).to include('AgentToolsQueue.pool_do_sidekiq')
  end

  it 'as 30 threads do processo principal nao pegam a fila (ela fica fora do sidekiq.yml)' do
    filas = YAML.safe_load(ERB.new(Rails.root.join('config/sidekiq.yml').read).result, permitted_classes: [Symbol])[:queues]

    expect(filas).not_to include('agent_tools')
  end

  it 'o initializer do Sidekiq configura o capsule' do
    expect(Rails.root.join('config/initializers/sidekiq.rb').read).to include('AgentToolsQueue.configurar(config)')
  end

  it 'o job usa a fila do modulo' do
    expect(Autonomia::Agents::Tools::HttpAssincronaJob::FILA.to_s).to eq(described_class::FILA)
  end
end

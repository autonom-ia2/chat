require 'rails_helper'

# #1426 (tema 4b) — a base mudou: espera 2 min depois da ÚLTIMA mudança e confere contradições se a base mudou desde a
# última conferência. Fora da Fase 2 e na Lia, nada. #3200: nenhum teste do material roda sozinho.
RSpec.describe Autonomia::Agents::Material::BaseMudouJob do
  include_context 'with material do agente'

  let(:contradicoes) { instance_double(Autonomia::Agents::Material::Contradicoes, conferir!: []) }

  before do
    material('cardapio.pdf')
    allow(Autonomia::Agents::Material::Contradicoes).to receive(:new).and_return(contradicoes)
  end

  def marca
    agent.reload.config.dig('conferencia_da_base', 'agendada')
  end

  it 'agenda com espera de 2 min; só o job da última marca segue (rajada vira uma rodada)', :aggregate_failures do
    expect { described_class.agendar(agent) }.to have_enqueued_job(described_class).at(a_value_within(5.seconds).of(2.minutes.from_now))
    primeira = marca
    described_class.agendar(agent)

    described_class.perform_now(agent.id, primeira)
    expect(contradicoes).not_to have_received(:conferir!)

    described_class.perform_now(agent.id, marca)
    expect(contradicoes).to have_received(:conferir!).once
  end

  it 'não enfileira mais nada depois de conferir (#3200: sem teste automático do material)' do
    described_class.agendar(agent)
    ultima = marca

    expect { described_class.perform_now(agent.id, ultima) }.not_to have_enqueued_job
  end

  it 'com a base igual à da última conferência, não confere contradições de novo' do
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base',
                                                       { 'hash_da_base' => Autonomia::Agents::Material.hash_da_base(agent) })
    described_class.agendar(agent)

    described_class.perform_now(agent.id, marca)

    expect(contradicoes).not_to have_received(:conferir!)
  end

  it 'fora da Fase 2 e na Lia: não agenda', :aggregate_failures do
    Autonomia::Agents::Fase2.desligar!(account)
    expect { described_class.agendar(agent.reload) }.not_to have_enqueued_job(described_class)

    Autonomia::Agents::Fase2.ligar!(account)
    agent.update_columns(agent_type: 'insurance_quote') # rubocop:disable Rails/SkipsModelValidations
    expect { described_class.agendar(agent.reload) }.not_to have_enqueued_job(described_class)
  end

  it 'a revisão de um material (recompute_overall!) agenda' do
    expect { Autonomia::Agents::Knowledge::Reviewer.recompute_overall!(agent) }.to have_enqueued_job(described_class)
  end
end

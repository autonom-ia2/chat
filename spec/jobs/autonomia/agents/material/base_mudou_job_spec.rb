require 'rails_helper'

# #1426 (tema 4b) — a base mudou: espera 2 min depois da ÚLTIMA mudança, confere contradições se a base mudou desde a
# última conferência e pede o autoteste automático só quando ele é permitido (30 min e base mudada). Fora da Fase 2 e na
# Lia, nada.
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

    expect { described_class.perform_now(agent.id, primeira) }.not_to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    expect(contradicoes).not_to have_received(:conferir!)

    expect { described_class.perform_now(agent.id, marca) }.to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    expect(contradicoes).to have_received(:conferir!).once
    expect(agent.reload.config.dig('autoteste', 'quando')).to eq('base_mudou')
  end

  it 'com a base igual à da última conferência, não confere contradições de novo' do
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'conferencia_da_base',
                                                       { 'hash_da_base' => Autonomia::Agents::Material.hash_da_base(agent) })
    described_class.agendar(agent)

    described_class.perform_now(agent.id, marca)

    expect(contradicoes).not_to have_received(:conferir!)
  end

  it 'autoteste automático: não repete com a mesma base nem antes de 30 min' do
    described_class.agendar(agent)
    described_class.perform_now(agent.id, marca)
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       agent.reload.config['autoteste'].merge('estado' => 'pronto'))
    described_class.agendar(agent)

    expect { described_class.perform_now(agent.id, marca) }.not_to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
  end

  it 'base mudada dentro dos 30 min: o aviso volta quando a rodada automática pode rodar, e então roda', :aggregate_failures do
    described_class.agendar(agent)
    described_class.perform_now(agent.id, marca)
    Autonomia::Agents::Agent.gravar_chave_do_material!(agent.id, 'autoteste',
                                                       agent.reload.config['autoteste'].merge('estado' => 'pronto'))
    ultima = Time.zone.parse(agent.reload.config.dig('autoteste', 'ultima_automatica'))
    material('horarios.pdf')
    described_class.agendar(agent)
    nova = marca

    expect { described_class.perform_now(agent.id, nova) }
      .to have_enqueued_job(described_class).with(agent.id, nova).at(a_value_within(1.second).of(ultima + 30.minutes))
    expect(agent.reload.config.dig('autoteste', 'estado')).to eq('pronto')

    travel_to(ultima + 31.minutes) do
      expect { described_class.perform_now(agent.id, nova) }.to have_enqueued_job(Autonomia::Agents::Material::AutotesteJob)
    end
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

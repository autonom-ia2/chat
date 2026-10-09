require 'rails_helper'

# Reaper de rascunhos órfãos do Construtor. Cada caso cobre um failure mode do job destrutivo:
# varrer o órfão de verdade, e NUNCA tocar agente ativo, rascunho com atividade recente (no agente
# ou na thread), agente manual, ou reabrir a janela por engano.
RSpec.describe Autonomia::Agents::ReapStaleDraftsJob, type: :job do
  let(:account) { create(:account) }

  def create_agent(status: :draft, enabled: false, mode: :guided, updated_ago: 3.days, instruction: nil)
    agent = Autonomia::Agents::Agent.create!(
      account: account, name: 'Novo agente', agent_type: 'custom',
      mode: mode, status: status, enabled: enabled, actuation: :external, instruction: instruction
    )
    # update_column pula o touch de updated_at para simular inatividade.
    agent.update_column(:updated_at, updated_ago.ago) # rubocop:disable Rails/SkipsModelValidations
    agent
  end

  it 'reaps a guided draft with no activity past the window' do
    orphan = create_agent

    described_class.new.perform

    expect(orphan.reload).to be_deleted
    expect(orphan.deleted_by_id).to be_nil
    expect(Audited.audit_class.where(auditable: orphan).sole.audited_changes).to include('reason' => 'stale_draft')
  end

  # #1035 — o Construtor não muda o status ao terminar: rascunho com instrução é agente PRONTO
  # esperando publicação. Apagá-lo depois de 48h perdia o agente inteiro.
  it 'never reaps a finished draft that has an instruction' do
    finished = create_agent(instruction: 'Atenda os clientes da loja.')

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(finished.id)).to be(true)
  end

  # #1035 — material enviado é trabalho do dono, mesmo velho e sem instrução.
  it 'never reaps a stale draft that has materials' do
    agent = create_agent
    source = Autonomia::Agents::Source.create!(
      account: account, agent: agent, source_type: 'txt', reference: 'faq.txt'
    )
    source.update_column(:updated_at, 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(agent.id)).to be(true)
    expect(Autonomia::Agents::Source.exists?(source.id)).to be(true)
  end

  it 'still reaps an empty draft whose instruction is a blank string' do
    orphan = create_agent(instruction: '')

    described_class.new.perform

    expect(orphan.reload).to be_deleted
  end

  it 'spares a draft whose build thread was active within the window' do
    agent = create_agent
    # thread recém-tocada mesmo com o agente velho — sinal de construção em andamento.
    Autonomia::Agents::BuildThread.create!(account: account, agent: agent)

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(agent.id)).to be(true)
  end

  it 'spares a stale draft with any user response in a build thread' do
    agent = create_agent
    thread = Autonomia::Agents::BuildThread.create!(
      account: account,
      agent: agent,
      messages: [{ 'role' => 'user', 'content' => 'Quero continuar depois.' }]
    )
    thread.update_column(:updated_at, 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.new.perform

    expect(agent.reload).not_to be_deleted
    expect(Autonomia::Agents::BuildThread.exists?(thread.id)).to be(true)
  end

  it 'archives an old thread without a user response but keeps the thread history' do
    agent = create_agent
    thread = Autonomia::Agents::BuildThread.create!(
      account: account,
      agent: agent,
      messages: [{ 'role' => 'assistant', 'content' => 'Qual é o nome?' }]
    )
    thread.update_column(:updated_at, 3.days.ago) # rubocop:disable Rails/SkipsModelValidations

    described_class.new.perform

    expect(agent.reload).to be_deleted
    expect(Autonomia::Agents::BuildThread.exists?(thread.id)).to be(true)
  end

  it 'spares a recently updated draft' do
    fresh = create_agent(updated_ago: 1.hour)

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(fresh.id)).to be(true)
  end

  it 'spares a stale draft that has a recently uploaded source (KB-first user)' do
    agent = create_agent
    # fonte recém-criada (upload horas depois, sem conversar) mantém o agente vivo.
    Autonomia::Agents::Source.create!(
      account: account, agent: agent, source_type: 'txt', reference: 'faq.txt'
    )

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(agent.id)).to be(true)
  end

  it 'still reaps the orphan when an unrelated recent thread has a nil agent (NULL subquery guard)' do
    orphan = create_agent
    # thread recém-criada SEM agente (nasce antes do link) — um NULL na subquery de NOT IN
    # zeraria toda a varredura se não fosse filtrado.
    Autonomia::Agents::BuildThread.create!(account: account)

    described_class.new.perform

    expect(orphan.reload).to be_deleted
  end

  it 'never reaps an active agent even when stale' do
    active = create_agent(status: :active, enabled: true)

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(active.id)).to be(true)
  end

  it 'never reaps a manual agent' do
    manual = create_agent(mode: :manual)

    described_class.new.perform

    expect(Autonomia::Agents::Agent.exists?(manual.id)).to be(true)
  end

  it 'clamps a non-positive window to the default instead of a future cutoff' do
    # janela negativa jogaria o cutoff no futuro e varreria até o rascunho fresco; o clamp evita isso.
    fresh = create_agent(updated_ago: 1.hour)

    with_modified_env AUTONOMIA_DRAFT_REAP_HOURS: '-1' do
      described_class.new.perform
    end

    expect(Autonomia::Agents::Agent.exists?(fresh.id)).to be(true)
  end
end

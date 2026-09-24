require 'rails_helper'

# O aquecimento do Guia depois do deploy (#636, revisão #637 do PR): só para quem JÁ TEM o agente
# do Guia criado — o embedding usa a chave de IA `crm_kanban_ai` DA CONTA, e aquecer toda conta
# elegível gastaria a chave de quem nunca abriu o painel do Guia. `Seed.eligible?`/
# `ensure_async_for` continuam sendo a fonte da elegibilidade e do dedupe por versão; este job só
# escolhe QUAIS contas visitar.
RSpec.describe Autonomia::Guide::WarmUpJob do
  # `Rails.cache` de produção é Redis; em teste é `:null_store` (nunca lembra do que gravou), que
  # deixaria a trava "uma varredura por versão" sempre passar — MemoryStore de verdade, como o
  # `Publicador::garantir_async` já testa (spec/services/autonomia/central_de_ajuda/publicador_spec.rb).
  around do |exemplo|
    cache_original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    exemplo.run
  ensure
    Rails.cache = cache_original
  end

  def criar_agente_guia(account)
    Autonomia::Agents::Agent.create!(
      account: account, name: 'Guia da Plataforma', agent_type: 'custom', status: :active, enabled: false,
      instruction: 'Guia.', config: { 'system_key' => Autonomia::Guide::Seed::SYSTEM_KEY }
    )
  end

  it 'aquece só quem já tem o agente do Guia, mesmo entre as elegíveis', :aggregate_failures do
    com_agente = create_account_and_user.first
    criar_agente_guia(com_agente)
    sem_agente = create_account_and_user.first

    allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for)

    described_class.new.perform

    expect(Autonomia::Guide::Seed).to have_received(:ensure_async_for).with(com_agente)
    expect(Autonomia::Guide::Seed).not_to have_received(:ensure_async_for).with(sem_agente)
  end

  it 'pula quem tem o agente mas deixou de ser elegível' do
    conta = create_account_and_user.first
    criar_agente_guia(conta)

    allow(Autonomia::Guide::Seed).to receive(:eligible?).with(conta).and_return(false)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for)

    described_class.new.perform

    expect(Autonomia::Guide::Seed).not_to have_received(:ensure_async_for)
  end

  # Blue/green sobe pelo menos duas instâncias de Sidekiq, e cada uma dispara `on(:startup)`.
  it 'roda a varredura uma vez por versão do KB — a segunda chamada não repete nada' do
    conta = create_account_and_user.first
    criar_agente_guia(conta)

    allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for)

    2.times { described_class.new.perform }

    expect(Autonomia::Guide::Seed).to have_received(:ensure_async_for).once
  end

  it 'erro numa conta não para o aquecimento das outras, e fica no log', :aggregate_failures do
    com_erro = create_account_and_user.first
    criar_agente_guia(com_erro)
    ok = create_account_and_user.first
    criar_agente_guia(ok)

    allow(Autonomia::Guide::Seed).to receive(:eligible?).and_return(true)
    allow(Autonomia::Guide::Seed).to receive(:ensure_async_for) do |account|
      raise 'falhou' if account.id == com_erro.id
    end
    allow(Rails.logger).to receive(:error)

    expect { described_class.new.perform }.not_to raise_error
    expect(Autonomia::Guide::Seed).to have_received(:ensure_async_for).with(ok)
    expect(Rails.logger).to have_received(:error).with(a_string_including(com_erro.id.to_s))
  end
end

require 'rails_helper'

RSpec.describe Autonomia::Automacao::CadeiaNoDespacho do
  include ActiveJob::TestHelper

  let(:cadeia) { Autonomia::Automacao::Cadeia }
  let(:conversation) { create(:conversation) }

  def com_a_flag
    conversation.account.enable_features!('automacao_fundacao')
  end

  def evento_com(origens)
    { conversation: conversation, autonomia_cadeia: { 'conta' => conversation.account_id, 'origens' => origens, 'raiz' => 'raiz-7' } }
  end

  it 'o evento despachado dentro de uma cadeia leva a lista de quem já rodou e a conta' do
    conversation
    clear_enqueued_jobs
    cadeia.com('regra:7', conversation.account_id) do
      Rails.configuration.dispatcher.dispatch('conversation.updated', Time.zone.now, conversation: conversation)
    end

    job = enqueued_jobs.find { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    dados = ActiveJob::Arguments.deserialize(job['arguments']).last
    expect(dados[:autonomia_cadeia]).to match('conta' => conversation.account_id, 'origens' => ['regra:7'], 'raiz' => be_present)
  end

  # F1.5: sem a flag, o evento disparado por uma regra sai exatamente como antes.
  it 'sem a flag, o evento de dentro de uma regra sai sem a chave' do
    rule = create(:automation_rule, account: conversation.account,
                                    actions: [{ action_name: 'change_priority', action_params: ['high'] }])

    AutomationRules::ActionService.new(rule, conversation.account, conversation.reload).perform

    eventos = enqueued_jobs.select { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    expect(eventos).not_to be_empty
    expect(eventos.map { |job| ActiveJob::Arguments.deserialize(job['arguments']).last }).to all(satisfy { |dados| !dados.key?(:autonomia_cadeia) })
  end

  it 'com a flag, o evento de dentro de uma regra leva a regra na cadeia' do
    com_a_flag
    rule = create(:automation_rule, account: conversation.account,
                                    actions: [{ action_name: 'change_priority', action_params: ['high'] }])

    AutomationRules::ActionService.new(rule, conversation.account, conversation.reload).perform

    eventos = enqueued_jobs.select { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    cadeias = eventos.map { |job| ActiveJob::Arguments.deserialize(job['arguments']).last[:autonomia_cadeia] }
    expect(cadeias).to include(a_hash_including('conta' => conversation.account_id, 'origens' => ["regra:#{rule.id}"]))
  end

  it 'fora de uma cadeia o evento sai como sempre' do
    Rails.configuration.dispatcher.dispatch('conversation.updated', Time.zone.now, conversation: conversation)

    job = enqueued_jobs.find { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    expect(ActiveJob::Arguments.deserialize(job['arguments']).last).not_to have_key(:autonomia_cadeia)
  end

  # Os listeners das regras rodam no job, em outra thread e depois do Current.reset: a cadeia volta com o evento.
  it 'o job devolve a cadeia aos listeners e a tira no fim' do
    com_a_flag
    vista = nil
    allow(Rails.configuration.dispatcher.async_dispatcher).to receive(:publish_event) do |_nome, _hora, dados|
      vista = [cadeia.origens, cadeia.raiz, dados]
    end

    EventDispatcherJob.perform_now('conversation.updated', Time.zone.now, evento_com(%w[regra:7 etapa:3]))

    expect(vista.first(2)).to eq([%w[regra:7 etapa:3], 'raiz-7'])
    expect(vista.last).not_to have_key(:autonomia_cadeia)
    expect(cadeia.origens).to eq([])
    expect(cadeia.raiz).to be_nil
  end

  # Rollback: o evento entrou na fila com a flag ligada e roda depois de ela ser desligada.
  it 'sem a flag na hora de rodar, os listeners trabalham sem cadeia e sem a chave' do
    vista = nil
    allow(Rails.configuration.dispatcher.async_dispatcher).to receive(:publish_event) { |_nome, _hora, dados| vista = [cadeia.ativa?, dados] }

    EventDispatcherJob.perform_now('conversation.updated', Time.zone.now, evento_com(%w[regra:7]))

    expect(vista.first).to be(false)
    expect(vista.last).not_to have_key(:autonomia_cadeia)
  end

  it 'sem a flag na hora de rodar, a ChamadaInterna de dentro do listener não zera o executed_by' do
    rule = create(:automation_rule, account: conversation.account)
    usuario = create(:user, account: conversation.account)
    visto = :nao_rodou
    allow(Rails.application).to receive(:call) do
      visto = Current.executed_by
      [200, {}, ['{}']]
    end
    allow(Rails.configuration.dispatcher.async_dispatcher).to receive(:publish_event) do
      Current.executed_by = rule
      Autonomia::Guide::ChamadaInterna.new(user: usuario).chamar('GET', '/x')
    end

    EventDispatcherJob.perform_now('conversation.updated', Time.zone.now, evento_com(%w[regra:7]))

    expect(visto).to eq(rule)
  ensure
    Current.reset
  end
end

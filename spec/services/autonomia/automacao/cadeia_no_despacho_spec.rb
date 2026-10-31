require 'rails_helper'

RSpec.describe Autonomia::Automacao::CadeiaNoDespacho do
  include ActiveJob::TestHelper

  let(:cadeia) { Autonomia::Automacao::Cadeia }
  let(:conversation) { create(:conversation) }

  it 'o evento despachado dentro de uma cadeia leva a lista de quem já rodou' do
    cadeia.com('regra:7') do
      Rails.configuration.dispatcher.dispatch('conversation.updated', Time.zone.now, conversation: conversation)
    end

    job = enqueued_jobs.find { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    dados = ActiveJob::Arguments.deserialize(job['arguments']).last
    expect(dados[:autonomia_cadeia]).to eq(['regra:7'])
  end

  it 'fora de uma cadeia o evento sai como sempre' do
    Rails.configuration.dispatcher.dispatch('conversation.updated', Time.zone.now, conversation: conversation)

    job = enqueued_jobs.find { |enfileirado| enfileirado['job_class'] == 'EventDispatcherJob' }
    expect(ActiveJob::Arguments.deserialize(job['arguments']).last).not_to have_key(:autonomia_cadeia)
  end

  # Os listeners das regras rodam no job, em outra thread e depois do Current.reset: a cadeia volta com o evento.
  it 'o job devolve a cadeia aos listeners e a tira no fim' do
    vista = nil
    allow(Rails.configuration.dispatcher.async_dispatcher).to receive(:publish_event) { vista = cadeia.origens }

    EventDispatcherJob.perform_now('conversation.updated', Time.zone.now,
                                   { conversation: conversation, autonomia_cadeia: %w[regra:7 etapa:3] })

    expect(vista).to eq(%w[regra:7 etapa:3])
    expect(cadeia.origens).to eq([])
  end
end

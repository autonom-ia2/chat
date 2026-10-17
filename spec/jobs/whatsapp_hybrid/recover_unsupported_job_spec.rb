require 'rails_helper'

# chat#1489: as tentativas de recuperação. Esperas de 5 s a 10 min e teto de 30 minutos desde o recebimento.
describe WhatsappHybrid::RecoverUnsupportedJob do
  include_context 'with a pending unsupported hybrid message'

  it 'recupera na primeira tentativa e não agenda outra' do
    stub_engine

    expect { described_class.perform_now(message.id) }.not_to have_enqueued_job(described_class)
    expect(message.reload.content_attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'sem a mensagem no motor, agenda a próxima com a espera seguinte' do
    stub_engine({ message: 'not found' }, status: 404)

    freeze_time do
      expect { described_class.perform_now(message.id) }
        .to have_enqueued_job(described_class).with(message.id, 1).at(15.seconds.from_now)
    end
  end

  it 'recupera na n-ésima tentativa' do
    stub_request(:get, engine_url).to_return({ status: 404, body: '{}' }, { status: 404, body: '{}' },
                                             { status: 200, body: engine_message.to_json,
                                               headers: { 'Content-Type' => 'application/json' } })

    described_class.perform_now(message.id, 0)
    described_class.perform_now(message.id, 1)
    expect(message.reload.content_attributes['hybrid_recovery']).to eq('pending')

    expect { described_class.perform_now(message.id, 2) }.not_to have_enqueued_job(described_class)
    expect(message.reload.content_attributes['hybrid_recovery']).to eq('recovered')
  end

  it 'depois das esperas da lista, segue de 10 em 10 minutos' do
    stub_engine({}, status: 404)

    freeze_time do
      expect { described_class.perform_now(message.id, 9) }
        .to have_enqueued_job(described_class).with(message.id, 10).at(10.minutes.from_now)
    end
  end

  it 'a última espera não passa do teto de 30 minutos' do
    stub_engine({}, status: 404)
    message.update_columns(created_at: 1.hour.ago.change(usec: 0)) # rubocop:disable Rails/SkipsModelValidations

    travel_to(message.created_at + 29.minutes) do
      expect { described_class.perform_now(message.id, 8) }
        .to have_enqueued_job(described_class).with(message.id, 9).at(message.created_at + 30.minutes)
    end
  end

  it 'desiste em 30 minutos: failed com timeout e nada agendado' do
    stub_engine({}, status: 404)

    travel_to(message.created_at + 30.minutes + 1.second) do
      expect { described_class.perform_now(message.id, 9) }.not_to have_enqueued_job(described_class)
    end
    expect(message.reload.content_attributes).to include('hybrid_recovery' => 'failed', 'hybrid_recovery_reason' => 'timeout')
    expect(message.content_attributes['is_unsupported']).to be(true)
  end

  it 'mensagem que não está pendente: não pergunta ao motor' do
    message.update!(content_attributes: message.content_attributes.merge('hybrid_recovery' => 'recovered'))

    described_class.perform_now(message.id)

    expect(a_request(:get, engine_url)).not_to have_been_made
  end

  it 'mensagem apagada: não faz nada' do
    expect { described_class.perform_now(0) }.not_to have_enqueued_job(described_class)
  end

  it 'erro inesperado numa tentativa não para as tentativas' do
    allow_any_instance_of(WhatsappHybrid::UnsupportedRecovery).to receive(:attempt!).and_raise(ActiveRecord::Deadlocked) # rubocop:disable RSpec/AnyInstance

    expect { described_class.perform_now(message.id) }.to have_enqueued_job(described_class).with(message.id, 1)
  end
end

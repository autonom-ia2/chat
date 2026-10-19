require 'rails_helper'

# #1367 (alavancas 0 e 4): o SubmitJob registra quanto o turno esperou na fila e, ao terminar, avisa a tela
# de quem abriu a conversa, que deixa de depender só da consulta periódica.
RSpec.describe Autonomia::Agents::Builder::SubmitJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account) }
  let(:thread) { Autonomia::Agents::BuildThread.create!(account: account, created_by: user) }
  let(:builder) { instance_double(Autonomia::Agents::Builder, run!: nil) }
  let(:event) { described_class::BUILD_THREAD_UPDATED }

  before do
    allow(Autonomia::Agents::Builder).to receive(:new).and_return(builder)
    allow(ActionCable.server).to receive(:broadcast)
  end

  def run_job(token, enqueued_at: nil)
    job = described_class.new(thread.id, token)
    job.enqueued_at = enqueued_at
    job.perform_now
  end

  it 'logs how long the turn waited in the queue' do
    freeze_time
    allow(Rails.logger).to receive(:info)

    run_job(thread.begin_build!, enqueued_at: 2.5.seconds.ago)

    expect(Rails.logger).to have_received(:info)
      .with("[Autonomia::Agents::Builder::SubmitJob] start thread=#{thread.id} queue_wait_ms=2500")
  end

  it 'tells only the creator screen that the thread changed, with ids and no content' do
    run_job(thread.begin_build!)

    expect(ActionCable.server).to have_received(:broadcast).once
    expect(ActionCable.server).to have_received(:broadcast)
      .with(user.pubsub_token, { event: event, data: { account_id: account.id, id: thread.id } })
  end

  it 'also tells the creator when the build failed' do
    allow(builder).to receive(:run!).and_raise(Crm::Ai::ResponsesClient::Error, 'ai_not_configured')
    token = thread.begin_build!

    run_job(token)

    expect(thread.reload).to be_failed
    expect(ActionCable.server).to have_received(:broadcast).with(user.pubsub_token, hash_including(event: event))
  end

  it 'stays quiet when the generation was superseded' do
    run_job('token-antigo')

    expect(Autonomia::Agents::Builder).not_to have_received(:new)
    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  it 'stays quiet when the thread has no creator' do
    thread.update!(created_by: nil)

    run_job(thread.begin_build!)

    expect(ActionCable.server).not_to have_received(:broadcast)
  end

  # #1426 — a foto da criação vai para a base depois que o turno foi gerado (o rascunho já existe).
  describe 'photos of the creation' do
    let(:fotos) { instance_double(Autonomia::Agents::Knowledge::FotosDaCriacao, para_base!: nil) }

    before { allow(Autonomia::Agents::Knowledge::FotosDaCriacao).to receive(:new).and_return(fotos) }

    it 'sends the photos of the turn to the base after the build' do
      run_job(thread.begin_build!)

      expect(Autonomia::Agents::Knowledge::FotosDaCriacao).to have_received(:new).with(thread)
      expect(fotos).to have_received(:para_base!)
    end

    it 'leaves the base alone when the generation was superseded' do
      run_job('token-antigo')

      expect(fotos).not_to have_received(:para_base!)
    end

    it 'never fails the turn because a photo could not go to the base, and reports it' do
      allow(fotos).to receive(:para_base!).and_raise(ActiveRecord::RecordInvalid)
      allow(Rails.logger).to receive(:error)
      tracker = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

      expect { run_job(thread.begin_build!) }.not_to raise_error
      expect(Rails.logger).to have_received(:error).with(/fotos_da_criacao_failed thread=#{thread.id}/)
      expect(ChatwootExceptionTracker).to have_received(:new).with(kind_of(ActiveRecord::RecordInvalid), account: account)
      expect(tracker).to have_received(:capture_exception)
      expect(ActionCable.server).to have_received(:broadcast).once
    end
  end

  it 'never fails the turn because the notice could not be sent' do
    allow(ActionCable.server).to receive(:broadcast).and_raise(Redis::CannotConnectError)

    expect { run_job(thread.begin_build!) }.not_to raise_error
  end
end

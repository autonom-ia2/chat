require 'rails_helper'

RSpec.describe Waha::HistoryImportJob do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:started_at) { 1.hour.ago.to_i }
  let(:before_cutoff) { 30.minutes.ago.to_i }
  let(:marker) do
    {
      'started_at' => started_at,
      'before' => before_cutoff,
      'working_at_ms' => (before_cutoff + 1) * 1000,
      'cutoff_version' => 2,
      'status' => 'waiting_connection',
      'chats_offset' => 0,
      'messages_offset' => 0,
      'chat_id' => nil,
      'pass' => 0,
      'imported' => 0,
      'unavailable_media' => 0
    }
  end
  let(:channel) do
    create(
      :channel_api,
      account: account,
      additional_attributes: {
        'provider' => 'waha',
        'session' => '5511999999999',
        'app_id' => 'app_123',
        'waha_history_import' => marker
      }
    )
  end
  let(:inbox) { channel.inbox }
  let(:client) { instance_double(Waha::Client) }
  let(:planner) { instance_double(Waha::ExistingInboxMigrationPlanner) }
  let(:plan) { instance_double(Waha::ExistingInboxMigrationPlanner::Plan, changes: []) }
  let(:importer) { instance_double(Waha::HistoryImporter) }
  let(:lock_manager) { instance_double(Redis::LockManager) }

  before do
    allow(Waha::Client).to receive(:new).and_return(client)
    allow(Waha::ExistingInboxMigrationPlanner).to receive(:new).with(client: client).and_return(planner)
    allow(planner).to receive(:build).with(channel).and_return(plan)
    allow(client).to receive(:get_session).with('5511999999999').and_return({ 'status' => 'WORKING' })
    allow(client).to receive(:history_source_ids_available?).and_return(true)
    allow(described_class).to receive(:set).and_call_original
    stub_const(
      'Waha::HistoryImporter',
      Class.new do
        def initialize(inbox:, client:, before:); end

        def import(chat_id:, messages:); end
      end
    )
    allow(Waha::HistoryImporter).to receive(:new).and_return(importer)
    allow(importer).to receive(:import).and_return(imported: 1, unavailable_media: 0)
  end

  it 'não consulta WAHA quando o marcador de onboarding não existe' do
    channel.update!(
      additional_attributes: channel.additional_attributes.except('waha_history_import')
    )

    expect(Waha::Client).not_to receive(:new)

    described_class.perform_now(inbox.id)
  end

  it 'deriva o cutoff do primeiro timestamp WORKING do provedor e o mantém nas passagens seguintes' do
    channel.update!(additional_attributes: channel.additional_attributes.merge('waha_history_import' => marker.merge('before' => 0)))
    allow(client).to receive(:list_chats).and_return([])
    connected_at = Time.current.change(usec: 0)
    working_at_ms = (connected_at.to_i * 1000) + 900
    channel.update!(additional_attributes: channel.additional_attributes.merge(
      'waha_history_import' => marker.merge('before' => 0, 'working_at_ms' => working_at_ms)
    ))

    travel_to(connected_at + 1.hour) { described_class.perform_now(inbox.id) }
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'before')).to eq(connected_at.to_i - 1)

    travel_to(connected_at + 2.hours) { described_class.perform_now(inbox.id) }
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'before')).to eq(connected_at.to_i - 1)
  end

  it 'permanece aguardando sem criar cutoff a partir do horário do polling' do
    channel.update!(additional_attributes: channel.additional_attributes.merge(
      'waha_history_import' => marker.except('before', 'working_at_ms', 'cutoff_version').merge('before' => 0)
    ))
    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class).with(inbox.id)
                                             .at(a_value_within(2.seconds).of(described_class::CONNECTION_RETRY_WAIT.from_now))

    expect(channel.reload.additional_attributes.dig('waha_history_import', 'before')).to eq(0)
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'waiting_reason')).to eq(
      'working_timestamp_missing'
    )
  end

  it 'preserva timestamp registrado enquanto a execução ainda possui estado antigo' do
    stale_marker = marker.except('working_at_ms', 'cutoff_version').merge('before' => 0)
    channel.update!(additional_attributes: channel.additional_attributes.merge('waha_history_import' => stale_marker))
    callback_written = false
    working_at_ms = (Time.current.to_i * 1000) + 400
    allow(client).to receive(:get_session).with('5511999999999') do
      unless callback_written
        callback_written = true
        current_attributes = channel.reload.additional_attributes
        current_marker = current_attributes.fetch('waha_history_import').merge(
          'working_at_ms' => working_at_ms,
          'cutoff_version' => described_class::CUTOFF_VERSION
        )
        channel.update!(additional_attributes: current_attributes.merge('waha_history_import' => current_marker))
      end
      { 'status' => 'WORKING' }
    end

    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class).with(inbox.id)
                                             .at(a_value_within(2.seconds).of(described_class::CONNECTION_RETRY_WAIT.from_now))

    registered = channel.reload.additional_attributes.fetch('waha_history_import')
    expect(registered).to include(
      'before' => 0,
      'working_at_ms' => working_at_ms,
      'cutoff_version' => described_class::CUTOFF_VERSION
    )

    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return([])
    described_class.perform_now(inbox.id)

    state = channel.reload.additional_attributes.fetch('waha_history_import')
    expect(state['before']).to eq((state['working_at_ms'] / 1000) - 1)
  end

  it 'rejeita divergência de timestamp sem sobrescrever o marcador atual' do
    current = channel.reload.additional_attributes.fetch('waha_history_import')
    stale = current.merge('working_at_ms' => current['working_at_ms'] + 1)

    expect do
      described_class.new(inbox.id).send(:persist_state, channel, stale)
    end.to raise_error(described_class::MarkerConflictError, 'history_marker_immutable_conflict')

    expect(channel.reload.additional_attributes.fetch('waha_history_import')).to include(
      'working_at_ms' => current['working_at_ms'],
      'cutoff_version' => current['cutoff_version']
    )
  end

  it 'reagenda a página concorrente em cinco segundos sem iniciar importação' do
    global_lock = described_class.new(inbox.id).send(:installation_lock_key)
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    allow(lock_manager).to receive(:lock).with(global_lock, described_class::LOCK_TIMEOUT).and_return(false)
    allow(lock_manager).to receive(:unlock).and_return(true)

    expect(Waha::Client).not_to receive(:new)
    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class).with(inbox.id)
                                             .at(a_value_within(1.second).of(described_class::GLOBAL_RETRY_WAIT.from_now))
    expect(lock_manager).not_to have_received(:unlock)
  end

  it 'stops before importing when the connector loses the stable source ID capability' do
    allow(client).to receive(:history_source_ids_available?).and_return(false)
    expect(client).not_to receive(:list_chats)

    described_class.perform_now(inbox.id)

    expect(channel.reload.additional_attributes['waha_history_import']).to include(
      'status' => 'failed', 'error_class' => 'Waha::HistoryImportJob::ConnectorCapabilityError'
    )
  end

  it 'fails closed for a future cutoff before querying WAHA' do
    attributes = channel.additional_attributes.merge('waha_history_import' => marker.merge('before' => 1.hour.from_now.to_i))
    channel.update!(additional_attributes: attributes)
    expect(client).not_to receive(:get_session)

    described_class.perform_now(inbox.id)

    expect(channel.reload.additional_attributes.dig('waha_history_import', 'status')).to eq('failed')
  end

  it 'mantém waiting_connection e não importa enquanto a sessão não está WORKING' do
    allow(client).to receive(:get_session).with('5511999999999').and_return({ 'status' => 'STOPPED' })

    expect(Waha::HistoryImporter).not_to receive(:new)

    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class)
      .with(inbox.id)
      .at(a_value_within(2.seconds).of(1.minute.from_now))

    expect(inbox.reload.channel.additional_attributes.dig('waha_history_import', 'status')).to eq('waiting_connection')
  end

  it 'continua aguardando a sessão pendente em intervalo maior depois de 24 horas' do
    old_marker = marker.merge('started_at' => 25.hours.ago.to_i)
    channel.update!(
      additional_attributes: channel.additional_attributes.merge('waha_history_import' => old_marker)
    )
    allow(client).to receive(:get_session).with('5511999999999').and_return({ 'status' => 'STOPPED' })

    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class)
      .with(inbox.id)
      .at(a_value_within(2.seconds).of(15.minutes.from_now))

    expect(inbox.reload.channel.additional_attributes.dig('waha_history_import', 'status')).to eq('waiting_connection')
  end

  it 'marca sessão FAILED como terminal e não consulta WAHA novamente' do
    allow(client).to receive(:get_session).with('5511999999999').and_return({ 'status' => 'FAILED' })

    described_class.perform_now(inbox.id)

    state = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(state).to include(
      'status' => 'failed',
      'error_class' => 'Waha::HistoryImportJob::ConnectionFailedError'
    )

    described_class.perform_now(inbox.id)

    expect(client).to have_received(:get_session).once
    expect(described_class).not_to have_been_enqueued
  end

  it 'interrompe em fail-closed quando o planner encontra divergência de identidade' do
    allow(planner).to receive(:build).with(channel).and_return(
      instance_double(Waha::ExistingInboxMigrationPlanner::Plan, changes: ['remote_chatwoot_app'])
    )

    expect(Waha::HistoryImporter).not_to receive(:new)
    expect(client).not_to receive(:list_chats)

    described_class.perform_now(inbox.id)

    expect(inbox.reload.channel.additional_attributes.dig('waha_history_import', 'status')).to eq('failed')
  end

  it 'persiste o cursor da página e agenda o próximo chat depois de importar uma página' do
    chats = [{ 'id' => '5511998888888@c.us' }]
    messages = [{ 'id' => 'message-1' }]
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return(chats)
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: '5511998888888@c.us', limit: 10, offset: 0, before: before_cutoff
    ).and_return(messages)

    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class)
      .with(inbox.id)
      .at(a_value_within(1.second).of(described_class::NEXT_PAGE_WAIT.from_now))

    state = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(state).to include(
      'chats_offset' => 0,
      'messages_offset' => 10,
      'chat_id' => '5511998888888@c.us',
      'imported' => 1,
      'pass' => 0,
      'before' => before_cutoff
    )

    clear_enqueued_jobs
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: '5511998888888@c.us', limit: 10, offset: 10, before: before_cutoff
    ).and_return([])
    allow(importer).to receive(:import).with(chat_id: '5511998888888@c.us', messages: [])
                                       .and_return(imported: 0, unavailable_media: 0)

    described_class.perform_now(inbox.id)

    expect(client).to have_received(:list_chats).once
    expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
      'chats_offset' => 1, 'messages_offset' => 0, 'chat_id' => nil, 'imported' => 1
    )
  end

  it 'retenta erro do cliente sem reler a lista depois de persistir o chat atual' do
    chat_id = '5511998888888@c.us'
    error = Waha::Client::Error.new('WAHA GET private-url body=private', status: 503)
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return([{ 'id' => chat_id }])
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: chat_id, limit: 10, offset: 0, before: before_cutoff
    ).and_raise(error)
    job = described_class.new(inbox.id)
    sanitized_error = nil
    allow(job).to receive(:retry_job).and_wrap_original do |original, options|
      sanitized_error = options.fetch(:error)
      original.call(options)
    end

    expect do
      job.perform_now
    end.to have_enqueued_job(described_class).with(inbox.id).on_queue('waha_history')

    expect(sanitized_error).to be_a(Waha::Client::Error).and have_attributes(
      message: 'waha_client_error status=503', cause: nil, backtrace: []
    )

    expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
      'status' => 'running', 'chats_offset' => 0, 'messages_offset' => 0, 'chat_id' => chat_id,
      'before' => before_cutoff
    )

    clear_enqueued_jobs
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: chat_id, limit: 10, offset: 0, before: before_cutoff
    ).and_return([{ 'id' => 'message-1' }])

    described_class.perform_now(inbox.id)

    expect(client).to have_received(:list_chats).once
    expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
      'messages_offset' => 10, 'chat_id' => chat_id, 'before' => before_cutoff
    )
  end

  it 'marca failed depois da quinta tentativa de erro do cliente' do
    chat_id = '5511998888888@c.us'
    error = Waha::Client::Error.new('temporary failure', status: 503)
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return([{ 'id' => chat_id }])
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: chat_id, limit: 10, offset: 0, before: before_cutoff
    ).and_raise(error)

    job = described_class.new(inbox.id)
    5.times { job.perform_now }

    state = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(state).to include(
      'status' => 'failed',
      'error_class' => 'Waha::Client::Error',
      'chats_offset' => 0,
      'messages_offset' => 0,
      'chat_id' => chat_id,
      'before' => before_cutoff
    )
    expect(client).to have_received(:list_chats).once
    expect(client).to have_received(:list_messages).exactly(5).times

    clear_enqueued_jobs
  end

  it 'agenda as três reconciliações com o cutoff imutável' do
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return([])

    described_class::RECONCILIATION_WAIT.each_with_index do |wait, pass|
      expect do
        described_class.perform_now(inbox.id)
      end.to have_enqueued_job(described_class).with(inbox.id).at(a_value_within(2.seconds).of(wait.from_now))

      expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
        'status' => 'running', 'pass' => pass + 1, 'before' => before_cutoff,
        'chats_offset' => 0, 'messages_offset' => 0, 'chat_id' => nil
      )
      clear_enqueued_jobs
    end
  end

  it 'conclui após as reconciliações e mantém before' do
    channel.update!(
      additional_attributes: channel.additional_attributes.merge(
        'waha_history_import' => marker.merge('status' => 'running', 'pass' => 3)
      )
    )
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return([])

    described_class.perform_now(inbox.id)

    state = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(state).to include('status' => 'completed', 'pass' => 3, 'before' => before_cutoff)
    expect(state['finished_at']).to be_a(Integer)
    expect(described_class).not_to have_been_enqueued
  end

  it 'ignora grupos e status sem importar e avança a página de chats' do
    chats = Array.new(10) do |index|
      { 'id' => index.even? ? "5511#{index}@g.us" : "status#{index}@broadcast" }
    end
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0).and_return(chats)

    expect(client).not_to receive(:list_messages)
    expect(Waha::HistoryImporter).not_to receive(:new)
    expect do
      described_class.perform_now(inbox.id)
    end.to have_enqueued_job(described_class).with(inbox.id)

    expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
      'status' => 'running', 'chats_offset' => 10, 'messages_offset' => 0, 'chat_id' => nil
    )
  end

  it 'falha fechado quando o marcador tem estado malformado' do
    channel.update!(
      additional_attributes: channel.additional_attributes.merge(
        'waha_history_import' => marker.except('before')
      )
    )
    expect(Waha::Client).not_to receive(:new)
    expect(planner).not_to receive(:build)

    described_class.perform_now(inbox.id)

    expect(inbox.reload.channel.additional_attributes.dig('waha_history_import', 'status')).to eq('failed')
    expect(inbox.reload.channel.additional_attributes.dig('waha_history_import', 'error_class')).to eq(
      'Waha::HistoryImportJob::InvalidStateError'
    )
  end

  it 'encerra página que excede o limite antes de avançar o cursor e libera o lock' do
    lock_key = "waha:history:#{inbox.id}"
    global_lock = described_class.new(inbox.id).send(:installation_lock_key)
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    allow(lock_manager).to receive(:lock).with(global_lock, 10.minutes).and_return(true)
    allow(lock_manager).to receive(:lock).with(lock_key, 10.minutes).and_return(true)
    allow(lock_manager).to receive(:unlock).with(global_lock).and_return(true)
    allow(lock_manager).to receive(:unlock).with(lock_key).and_return(true)
    allow(Timeout).to receive(:timeout).with(
      described_class::PAGE_TIMEOUT, described_class::PageTimeoutError
    ).and_raise(described_class::PageTimeoutError)
    expect(client).not_to receive(:list_chats)

    described_class.perform_now(inbox.id)

    state = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(state).to include(
      'status' => 'failed',
      'error_class' => 'Waha::HistoryImportJob::PageTimeoutError',
      'chats_offset' => 0,
      'messages_offset' => 0,
      'chat_id' => nil,
      'before' => before_cutoff
    )
    expect(lock_manager).to have_received(:lock).with(lock_key, 10.minutes)
    expect(lock_manager).to have_received(:unlock).with(lock_key)
    expect(lock_manager).to have_received(:unlock).with(global_lock)
  end

  it 'propaga conflito de lock e usa TTL de dez minutos por inbox' do
    allow(Redis::LockManager).to receive(:new).and_return(lock_manager)
    global_lock = described_class.new(inbox.id).send(:installation_lock_key)
    allow(lock_manager).to receive(:lock).with(global_lock, 10.minutes).and_return(true)
    allow(lock_manager).to receive(:unlock).with(global_lock).and_return(true)
    allow(lock_manager).to receive(:lock).with("waha:history:#{inbox.id}", 10.minutes).and_return(false)

    expect do
      described_class.perform_now(inbox.id)
    end.to raise_error(MutexApplicationJob::LockAcquisitionError)
  end

  it 'marca a página como failed sem avançar o cursor e não consulta de novo' do
    allow(client).to receive(:list_chats).with('5511999999999', limit: 10, offset: 0)
                                         .and_return([{ 'id' => '5511998888888@c.us' }])
    allow(client).to receive(:list_messages).with(
      '5511999999999', chat_id: '5511998888888@c.us', limit: 10, offset: 0, before: before_cutoff
    ).and_return([{ 'id' => 'message-1' }])
    allow(importer).to receive(:import).and_raise(StandardError)

    described_class.perform_now(inbox.id)

    failed = inbox.reload.channel.additional_attributes['waha_history_import']
    expect(failed).to include(
      'status' => 'failed',
      'error_class' => 'StandardError',
      'chats_offset' => 0,
      'messages_offset' => 0,
      'chat_id' => '5511998888888@c.us',
      'imported' => 0
    )

    expect(client).not_to receive(:get_session)
    expect(Waha::HistoryImporter).not_to receive(:new)
    described_class.perform_now(inbox.id)

    expect(inbox.reload.channel.additional_attributes['waha_history_import']).to include(
      'status' => 'failed', 'chats_offset' => 0, 'messages_offset' => 0,
      'chat_id' => '5511998888888@c.us', 'imported' => 0
    )
  end

  it 'não consulta nem importa novamente quando já está completed' do
    completed = marker.merge('status' => 'completed', 'finished_at' => Time.current.to_i)
    channel.update!(
      additional_attributes: channel.additional_attributes.merge('waha_history_import' => completed)
    )

    expect(Waha::Client).not_to receive(:new)
    expect(Waha::HistoryImporter).not_to receive(:new)

    described_class.perform_now(inbox.id)
  end
end

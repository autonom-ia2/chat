require 'rails_helper'
require 'timeout'

RSpec.describe Relationships::ValuePatch, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:contact) { create(:contact, account: account) }
  let!(:definition) do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute', attribute_key: 'position',
                                         attribute_display_type: 'list', attribute_values: %w[CEO CFO])
  end
  let(:payload) { { 'key' => 'position', 'value' => 'CEO', 'previous' => nil } }
  let(:workers) { [] }
  let(:writer_pid) { Queue.new }
  let(:legacy_pattern) do
    File.readlines(Rails.root.join('spec/jobs/inboxes/update_widget_pre_chat_custom_fields_job_spec.rb'))
        .find { |line| line.include?("'regex_pattern' =>") }.split("'")[3]
  end

  after do
    workers.each { |worker| worker.join(15) || worker.kill.join }
    account.contacts.destroy_all
    account.custom_attribute_definitions.destroy_all
    account.reload.destroy!
  end

  def wait_for_lock(worker)
    pid = writer_pid.pop(timeout: 10)
    raise 'Writer did not report its connection' unless pid

    Timeout.timeout(10) do
      until ActiveRecord::Base.connection.select_value("SELECT pg_backend_pid() = ANY(pg_blocking_pids(#{Integer(pid)}))")
        raise 'Writer completed without the required overlap' unless worker.alive?

        sleep 0.01
      end
    end
  end

  %w[removed_option deleted_definition legacy_validation].each do |change|
    it "rechecks #{change} committed while the value writer was waiting" do
      pattern = legacy_pattern if change == 'legacy_validation'
      definition.with_lock do
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            record = Contact.find(contact.id)
            writer_pid << connection.raw_connection.backend_pid
            described_class.new(record, 'contact_attribute').update!(payload)
          rescue StandardError => e
            e.class.name
          end
        end
        wait_for_lock(workers.last)
        case change
        when 'removed_option' then definition.update!(attribute_values: ['CFO'])
        when 'deleted_definition' then definition.destroy!
        when 'legacy_validation' then definition.update!(regex_pattern: pattern)
        end
      end
      expected = change == 'deleted_definition' ? 'ActiveRecord::RecordNotFound' : 'Relationships::Configuration::Invalid'
      expect(workers.last.value).to eq(expected)
      expect(contact.reload.custom_attributes).to eq({})
    end
  end

  it 'keeps the definition locked until the outer value transaction commits without reversing Configuration locks' do
    ActiveRecord::Base.transaction do
      described_class.new(contact, 'contact_attribute').update!(payload)
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.raw_connection.backend_pid
          Relationships::Configuration.new(Account.find(account.id)).update!(
            'revision' => 0,
            'definition' => { 'id' => definition.id, 'revision' => definition.updated_at.iso8601(6), 'attribute_values' => ['CFO'] }
          )
        end
      end
      wait_for_lock(workers.last)
      expect(definition.reload.attribute_values).to eq(%w[CEO CFO])
    end
    expect(workers.last.value.fetch(:configuration)['revision']).to eq(1)
    expect(definition.reload.attribute_values).to eq(['CFO'])
    expect(contact.reload.custom_attributes).to eq('position' => 'CEO')
  end

  it 'retains the definition lock while waiting for the record' do
    patch_pid = Queue.new
    connection = ActiveRecord::Base.connection
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |patch_connection|
          patch_pid << patch_connection.raw_connection.backend_pid
          writer_pid << patch_connection.raw_connection.backend_pid
          described_class.new(Contact.find(contact.id), 'contact_attribute').update!(payload)
        end
      end
      wait_for_lock(workers.last)
      patch_backend = patch_pid.pop(timeout: 10)
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |definition_connection|
          writer_pid << definition_connection.raw_connection.backend_pid
          CustomAttributeDefinition.find(definition.id).update!(attribute_values: ['CFO'])
        end
      end
      definition_backend = writer_pid.pop(timeout: 10)
      Timeout.timeout(10) do
        until connection.select_value("SELECT #{Integer(patch_backend)} = ANY(pg_blocking_pids(#{Integer(definition_backend)}))")
          raise 'Definition changed before the value transaction committed' unless workers.last.alive?

          sleep 0.01
        end
      end
    end
    workers.each(&:value)
    expect(contact.reload.custom_attributes).to eq('position' => 'CEO')
    expect(definition.reload.attribute_values).to eq(['CFO'])
  end
end

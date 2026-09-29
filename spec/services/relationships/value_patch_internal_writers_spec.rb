require 'rails_helper'
require 'timeout'

RSpec.describe Relationships::ValuePatch do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let(:workers) { [] }
  let(:writer_pid) { Queue.new }
  let!(:contact) { create(:contact, account: account, identifier: 'internal-writer', custom_attributes: { 'untouched' => 'keep' }) }

  before do
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'confirmed', attribute_display_type: 'text')
  end

  after do
    workers.each { |worker| worker.join(15) || worker.kill.join }
    account.autonomia_prospecting_leads.destroy_all
    account.data_imports.destroy_all
    account.contacts.destroy_all
    account.companies.destroy_all
    account.custom_attribute_definitions.destroy_all
    account.reload.destroy!
  end

  # Reused barrier: assert PostgreSQL actually blocked the writer, not merely that two threads ran.
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

  it 'keeps a confirmed value when CSV import found the contact before the commit' do
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.raw_connection.backend_pid
          DataImport::ContactManager.new(Account.find(account.id)).build_contact(
            { identifier: contact.identifier, imported: 'csv' }.with_indifferent_access
          )
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    expect(workers.last.value).to be_persisted
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'imported' => 'csv', 'untouched' => 'keep')
  end

  it 'refreshes an extractor snapshot and rechecks whether the target is already filled' do
    admin = create(:user, account: account, role: :administrator)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    create(:custom_attribute_definition, account: account, attribute_model: 'contact_attribute',
                                         attribute_key: 'extracted', attribute_display_type: 'text')
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Synthetic', contact: contact, currency: 'BRL')
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          stale_card = Crm::Card.find(card.id)
          stale_card.contact
          writer_pid << connection.raw_connection.backend_pid
          Crm::Ai::AttributeExtractorApplier.new(card: stale_card, prefix: '', extracted_attributes: {
                                                   contact: [{ key: 'confirmed', value: 'ai', confidence: 1 },
                                                             { key: 'extracted', value: 'ai', confidence: 1 }]
                                                 }).perform
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    result = workers.last.value
    expect(result.rejected).to include(hash_including(key: 'confirmed', reason: 'already_filled'))
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'extracted' => 'ai', 'untouched' => 'keep')
    expect(card.reload.metadata.dig('ai', 'extracted_attributes').keys).to eq(['extracted'])
  ensure
    workers.each { |worker| worker.join(15) || worker.kill.join }
    card&.destroy!
    pipeline&.destroy!
    admin&.destroy!
  end

  it 'merges the shared provider importer payload into the current JSON' do
    data_import = create(:data_import, :freshdesk, account: account)
    payload = JSON.parse(Rails.root.join('spec/fixtures/data_import/freshdesk/contact.json').read)
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          stale_contact = Contact.find(contact.id)
          importer = DataImports::Freshdesk::Importer.new(data_import: data_import)
          writer_pid << connection.raw_connection.backend_pid
          importer.send(:update_existing_contact, stale_contact, payload)
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    workers.last.value
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'freshdesk_contact_id' => payload.fetch('id'), 'untouched' => 'keep')
  end

  it 'refreshes the existing contact before prospecting enrichment' do
    company = create(:company, account: account)
    lead = Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'lock-fixture',
                                                name: 'Synthetic', contact: contact, country: 'BR')
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          stale_lead = Autonomia::Prospecting::Lead.find(lead.id)
          stale_lead.contact
          writer_pid << connection.raw_connection.backend_pid
          Autonomia::Prospecting::ContactConverter.new(lead: stale_lead, user: nil, company: company).perform
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    workers.last.value
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'autonomia_prospecting_lead_id' => lead.id, 'untouched' => 'keep')
  end

  it 'refreshes contact identification before merging only the supplied attributes' do
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          stale_contact = Contact.find(contact.id)
          writer_pid << connection.raw_connection.backend_pid
          ContactIdentifyAction.new(contact: stale_contact, params: { custom_attributes: { widget: 'provided' } }).perform
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    workers.last.value
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'widget' => 'provided', 'untouched' => 'keep')
  end

  it 'keeps both contacts current when merging their JSON' do
    mergee = create(:contact, account: account, custom_attributes: { 'merged' => 'source' })
    contact.with_lock do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          base_contact = Contact.find(contact.id)
          writer_pid << connection.raw_connection.backend_pid
          ContactMergeAction.new(account: account, base_contact: base_contact, mergee_contact: mergee).perform
        end
      end
      wait_for_lock(workers.last)
      described_class.new(contact, 'contact_attribute').update!('key' => 'confirmed', 'value' => 'human', 'previous' => nil)
    end
    workers.last.value
    expect(contact.reload.custom_attributes).to include('confirmed' => 'human', 'merged' => 'source', 'untouched' => 'keep')
  end
end

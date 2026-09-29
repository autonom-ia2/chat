require 'rails_helper'
require 'timeout'

RSpec.describe Relationships::CompanyPreviewJob do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:message) { create(:message, account: account) }
  let!(:attachment) do
    message.attachments.create!(account: account, file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
  end

  before { account.enable_features!('companies', 'relationships_company_media') }

  after do
    Attachment.where(account_id: account.id).destroy_all
    account.messages.destroy_all
    account.conversations.destroy_all
    account.contacts.destroy_all
    account.reload.destroy!
  end

  it 'keeps 25 blobs pending through four busy-slot attempts and converts after capacity returns' do
    files = [attachment] + Array.new(24) { message.attachments.create!(account: account, file: attachment.file.blob) }
    files.each { |file| described_class.request(file) }
    connection = Attachment.connection
    main_pid = connection.raw_connection.backend_pid
    worker = nil
    connection.execute("SELECT pg_advisory_lock(#{described_class::LOCK_ID})")
    begin
      worker = Thread.new do
        Attachment.connection_pool.with_connection do |worker_connection|
          4.times do
            files.each { |file| described_class.perform_now(file.id, file.file.blob_id) }
          end
          worker_connection.raw_connection.backend_pid
        end
      end
      Timeout.timeout(30) { worker.join }
      expect(worker.value).not_to eq(main_pid)
      files.each do |file|
        expect(file.reload.meta['relationship_preview']).to include('status' => 'pending', 'failure_count' => 0)
      end
    ensure
      worker&.join(1) || worker&.kill&.join
      connection.execute("SELECT pg_advisory_unlock(#{described_class::LOCK_ID})")
    end
    described_class.perform_now(attachment.id, attachment.file.blob_id)
    expect(described_class.ready?(attachment.reload)).to be(true)
  end
end

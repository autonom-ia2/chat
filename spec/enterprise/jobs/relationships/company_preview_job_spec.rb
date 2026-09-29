require 'rails_helper'

RSpec.describe Relationships::CompanyPreviewJob do
  let(:account) { create(:account) }
  let(:attachment) do
    create(:message, account: account).attachments.create!(account: account,
                                                           file: fixture_file_upload(
                                                             Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'
                                                           ))
  end

  it 'deduplicates demand and only enqueues on the existing low queue' do
    expect { 2.times { described_class.request(attachment) } }.to have_enqueued_job(described_class).exactly(:once).on_queue('low')
    expect(attachment.reload.meta.dig('relationship_preview', 'status')).to eq('pending')
  end

  it 'does not enqueue oversized files' do
    attachment.file.blob.update!(byte_size: described_class::MAX_BYTES + 1)
    expect { expect(described_class.request(attachment)).to eq('unavailable') }.not_to have_enqueued_job(described_class)
  end

  it 'does not convert after the account flag is disabled' do
    expect(Relationships::PreviewRenderer).not_to receive(:new)
    described_class.perform_now(attachment.id, attachment.file.blob_id)
    expect(attachment.relationship_preview).not_to be_attached
  end

  context 'with capacity contention and blob replacement' do
    let(:account) { create(:account) }
    let(:message) { create(:message, account: account) }
    let(:attachment) do
      message.attachments.create!(account: account, file: fixture_file_upload(Rails.root.join('spec/assets/sample.pdf'), 'application/pdf'))
    end

    before { account.enable_features!('companies', 'relationships_company_media') }

    it 'keeps 25 valid files pending when the conversion slot is busy beyond three attempts' do
      blob = attachment.file.blob
      files = [attachment] + Array.new(24) { message.attachments.create!(account: account, file: blob) }
      connection = Attachment.connection
      allow(connection).to receive(:select_value).and_call_original
      allow(connection).to receive(:select_value).with("SELECT pg_try_advisory_lock(#{described_class::LOCK_ID})").and_return(false)
      expect(Relationships::PreviewRenderer).not_to receive(:new)
      files.each do |file|
        described_class.request(file)
        4.times { described_class.perform_now(file.id, blob.id) }
        expect(file.reload.meta.dig('relationship_preview', 'status')).to eq('pending')
      end
    end

    it 'allows fresh demand after capacity wait expires' do
      described_class.request(attachment)
      travel 11.minutes do
        expect { described_class.request(attachment.reload) }.to have_enqueued_job(described_class)
        expect(attachment.meta.dig('relationship_preview', 'status')).to eq('pending')
      end
    end

    %i[download upload].each do |operation|
      it "recovers the same blob after one transient storage #{operation} failure" do
        described_class.request(attachment)
        blob_id = attachment.file.blob_id
        service = attachment.file.blob.service
        calls = 0
        allow(service).to receive(operation).and_wrap_original do |original, *args, **kwargs, &block|
          calls += 1
          raise IOError, 'Synthetic storage outage' if calls == 1

          original.call(*args, **kwargs, &block)
        end

        expect { described_class.perform_now(attachment.id, blob_id) }
          .to have_enqueued_job(described_class).with(attachment.id, blob_id).at(a_value_within(1).of(10.seconds.from_now))
        expect(attachment.reload.meta['relationship_preview']).to include('status' => 'pending', 'failure' => 'transient', 'failure_count' => 1)
        expect(described_class.ready?(attachment)).to be(false)
        expect { described_class.request(attachment) }.not_to have_enqueued_job(described_class)
        travel 11.seconds do
          described_class.perform_now(attachment.id, blob_id)
          expect(described_class.request(attachment.reload)).to eq('ready')
          expect(attachment.file.blob_id).to eq(blob_id)
          expect(attachment.relationship_preview.download.byteslice(0, 2)).to eq("\xFF\xD8".b)
        end
      end
    end

    it 'purges the persisted derivative after a partial storage upload failure' do
      described_class.request(attachment)
      original_blob_id = attachment.file.blob_id
      service = attachment.file.blob.service
      failed_key = nil
      allow(service).to receive(:upload).and_wrap_original do |original, *args, **kwargs, &block|
        failed_key = args.first
        original.call(*args, **kwargs, &block)
        raise IOError, 'Synthetic failure after storage wrote the derivative'
      end

      described_class.perform_now(attachment.id, original_blob_id)
      orphan = ActiveStorage::Blob.find_by!(key: failed_key)
      expect(orphan.filename.to_s).to eq('preview.jpg')
      expect(service.exist?(failed_key)).to be(true)
      expect(ActiveStorage::PurgeJob).to have_been_enqueued.with(orphan)
      expect(attachment.reload.meta['relationship_preview']).to include('failure' => 'transient', 'failure_count' => 1)
      expect(described_class.ready?(attachment)).to be(false)
      perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
      expect({ record: ActiveStorage::Blob.exists?(orphan.id), stored_file: service.exist?(failed_key) }).to eq(record: false, stored_file: false)
      expect(attachment.reload.file.blob_id).to eq(original_blob_id)
    end

    it 'bounds transient retries with backoff and permits GET demand after the TTL' do
      described_class.request(attachment)
      blob_id = attachment.file.blob_id
      allow(attachment.file.blob.service).to receive(:download).and_raise(IOError, 'Synthetic storage outage')
      described_class.perform_now(attachment.id, blob_id)
      travel 11.seconds
      expect { described_class.perform_now(attachment.id, blob_id) }
        .to have_enqueued_job(described_class).at(a_value_within(1).of(20.seconds.from_now))
      travel 21.seconds
      expect { described_class.perform_now(attachment.id, blob_id) }.not_to have_enqueued_job(described_class)
      expect(attachment.reload.meta['relationship_preview']).to include('status' => 'unavailable', 'failure' => 'transient', 'failure_count' => 3)
      expect { described_class.request(attachment) }.not_to have_enqueued_job(described_class)
      travel 11.minutes
      expect { expect(described_class.request(attachment.reload)).to eq('pending') }.to have_enqueued_job(described_class)
      expect(attachment.meta.dig('relationship_preview', 'failure_count')).to eq(0)
    ensure
      travel_back
    end

    it 'keeps a determined corrupt-content fallback without spending transient retries' do
      attachment.file.attach(io: StringIO.new('%PDF-corrupt'), filename: 'broken.pdf', content_type: 'application/pdf')
      described_class.request(attachment)
      expect { described_class.perform_now(attachment.id, attachment.file.blob_id) }.not_to have_enqueued_job(described_class)
      expect(attachment.reload.meta['relationship_preview']).to include('status' => 'unavailable', 'failure' => 'content', 'failure_count' => 0)
      travel 11.minutes do
        expect { expect(described_class.request(attachment)).to eq('unavailable') }.not_to have_enqueued_job(described_class)
      end
    end

    it 'expires historical unavailable states without a classified content failure' do
      attachment.update!(meta: { relationship_preview: { status: 'unavailable', blob_id: attachment.file.blob_id, requested_at: 0 } })
      expect { expect(described_class.request(attachment)).to eq('pending') }.to have_enqueued_job(described_class)
    end

    it 'allows an explicit internal force for the same blob under the attachment lock' do
      described_class.request(attachment)
      expect do
        attachment.with_lock { described_class.enqueue_preview(attachment, attachment.file.blob, force: true) }
      end.to have_enqueued_job(described_class)
    end

    it 'does not serve the derivative when the source blob changes' do
      described_class.request(attachment)
      File.open(Rails.root.join('spec/assets/sample.png')) do |file|
        attachment.relationship_preview.attach(io: file, filename: 'preview.jpg', content_type: 'image/jpeg')
      end
      attachment.update!(meta: { relationship_preview: { status: 'ready', blob_id: attachment.file.blob_id,
                                                         ready_blob_id: attachment.file.blob_id } })
      expect(described_class.ready?(attachment)).to be(true)
      File.open(Rails.root.join('spec/assets/sample.png')) do |file|
        attachment.file.attach(io: file, filename: 'replacement.png', content_type: 'image/png')
      end
      expect(described_class.ready?(attachment.reload)).to be(false)
      expect { described_class.request(attachment) }.to have_enqueued_job(described_class)
    end
  end
end

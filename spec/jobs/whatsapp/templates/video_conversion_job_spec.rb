require 'rails_helper'

# #2370: o fluxo feliz e a recusa da Meta estão no spec do controller (POST media: vídeo convertido fora do pedido).
RSpec.describe Whatsapp::Templates::VideoConversionJob, :aggregate_failures do
  let(:conversion) { Whatsapp::Templates::VideoConversion }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false).inbox
  end
  let(:file) { Rack::Test::UploadedFile.new(StringIO.new('mov'), 'video/quicktime', original_filename: 'IMG_0001.MOV') }
  let(:id) { conversion.start(inbox: inbox, account_user: admin.account_users.first, file: file) }

  def originals = ActiveStorage::Blob.where('metadata LIKE ?', '%video_conversion%')

  it 'start agenda a conversão e a limpeza do original para depois do prazo do pedido' do
    id

    expect(described_class).to have_been_enqueued.with(id)
    expect(Whatsapp::Templates::VideoConversionCleanupJob).to have_been_enqueued.with(originals.sole.id)
  end

  it 'start que falha depois de guardar o original: apaga o original' do
    allow(described_class).to receive(:perform_later).and_raise(RedisClient::CannotConnectError)

    expect { id }.to raise_error(RedisClient::CannotConnectError)
    expect(originals).to be_empty
  end

  it 'erro inesperado: encerra como failed (a tela para de esperar) e apaga o original' do
    allow(conversion).to receive(:convert_and_store).and_raise(RuntimeError, 'quebrou')
    id

    described_class.perform_now(id)

    expect(conversion.read(id)).to include('status' => 'failed', 'error' => 'video_unreadable')
    expect(originals).to be_empty
  end

  it 'falha ao apagar o original depois do done: o resultado continua done (a limpeza agendada apaga depois)' do
    allow(conversion).to receive(:convert_and_store).and_return('handle' => 'h')
    allow_any_instance_of(ActiveStorage::Blob).to receive(:purge).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'x')) # rubocop:disable RSpec/AnyInstance
    id

    described_class.perform_now(id)

    expect(conversion.read(id)).to include('status' => 'done', 'result' => { 'handle' => 'h' })
  end

  it 'pedido já concluído (reentregue depois de pronto): não roda de novo nem vira failed' do
    conversion.finish(id, 'status' => 'done', 'result' => { 'handle' => 'h' })
    allow(conversion).to receive(:convert_and_store)

    described_class.perform_now(id)
    conversion.finish(id, 'status' => 'failed', 'error' => 'video_unreadable')

    expect(conversion).not_to have_received(:convert_and_store)
    expect(conversion.read(id)['status']).to eq('done')
  end

  it 'outra conversão rodando: volta para a fila sem converter' do
    allow(conversion).to receive(:convert_and_store)
    id
    Redis::Alfred.set(conversion::LOCK_KEY, 'outro', nx: true, ex: 60)

    expect { described_class.perform_now(id) }.to have_enqueued_job(described_class).with(id)
    expect(conversion).not_to have_received(:convert_and_store)
    expect(conversion.read(id)['status']).to eq('pending')
  ensure
    Redis::Alfred.delete(conversion::LOCK_KEY)
  end

  it 'limpeza agendada: apaga só o original de conversão que ficou' do
    original = originals.find(conversion.read(id)['blob_id'])
    other = ActiveStorage::Blob.create_and_upload!(io: StringIO.new('foto'), filename: 'foto.png')

    Whatsapp::Templates::VideoConversionCleanupJob.perform_now(original.id)
    Whatsapp::Templates::VideoConversionCleanupJob.perform_now(other.id)

    expect(ActiveStorage::Blob.exists?(original.id)).to be(false)
    expect(ActiveStorage::Blob.exists?(other.id)).to be(true)
  end
end

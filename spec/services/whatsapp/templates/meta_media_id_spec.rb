require 'rails_helper'

# #2367: o arquivo do topo e dos cartões vai à Meta pelo id da mídia, subido na caixa que envia (pelo link, a busca da
# Meta falha com 131053). O disparo da campanha, com a Graph falsa, está em header_media_spec e send_params_spec.
RSpec.describe Whatsapp::Templates::MetaMediaId, :aggregate_failures do
  let(:channel) { create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false) }
  let(:blob) { ActiveStorage::Blob.create_and_upload!(io: StringIO.new('mp4'), filename: 'promo.mp4', content_type: 'video/mp4') }

  describe '.upload' do
    it 'sobe o arquivo pelo número da caixa e devolve o id' do
      uploads = stub_meta_media_upload

      expect(described_class.upload(blob, channel.inbox)).to eq('media_1')
      expect(uploads).to eq(['promo.mp4'])
      expect(a_request(:post, "https://graph.facebook.com/v22.0/#{channel.provider_config['phone_number_id']}/media")).to have_been_made.once
    end

    it 'devolve nil quando a Meta recusa (o envio segue pelo link)' do
      stub_meta_media_upload(status: 400)

      expect(described_class.upload(blob, channel.inbox)).to be_nil
    end

    it 'o mesmo arquivo na mesma caixa sobe uma vez; em outra caixa sobe de novo (o id só vale no número que subiu)' do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
      uploads = stub_meta_media_upload
      other = create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
      other.update!(provider_config: other.provider_config.merge('phone_number_id' => '987654321'))

      ids = [described_class.upload(blob, channel.inbox), described_class.upload(blob, channel.inbox), described_class.upload(blob, other.inbox)]

      expect(ids).to eq(%w[media_1 media_1 media_2])
      expect(uploads.size).to eq(2)
    end

    it 'erro na subida (ex.: arquivo ilegível) devolve nil e não interrompe o envio' do
      allow(Whatsapp::MediaUploadService).to receive(:new).and_raise(Aws::S3::Errors::ServiceError.new(nil, 'boom'))
      allow(Rails.logger).to receive(:warn)

      expect(described_class.upload(blob, channel.inbox)).to be_nil
      expect(Rails.logger).to have_received(:warn).with(include('upload_failed').and(include('Aws::S3::Errors::ServiceError')))
    end

    it 'não sobe com a subida desligada (WHATSAPP_MEDIA_UPLOAD_STRATEGY=link)' do
      uploads = stub_meta_media_upload

      with_modified_env(WHATSAPP_MEDIA_UPLOAD_STRATEGY: 'link') do
        expect(described_class.upload(blob, channel.inbox)).to be_nil
      end
      expect(uploads).to be_empty
    end

    it 'não sobe numa caixa do WhatsApp que não é a API oficial' do
      uploads = stub_meta_media_upload
      dialog = create(:channel_whatsapp, provider: 'default', validate_provider_config: false, sync_templates: false)

      expect(described_class.upload(blob, dialog.inbox)).to be_nil
      expect(described_class.upload(blob, nil)).to be_nil
      expect(uploads).to be_empty
    end
  end

  describe '.parameter' do
    it 'monta o parâmetro pelo id, com o nome só no documento' do
      expect(described_class.parameter({ 'media_id' => '9', 'media_type' => 'video', 'media_name' => 'promo.mp4' }))
        .to eq(type: 'video', video: { id: '9' })
      expect(described_class.parameter({ 'media_id' => '9', 'media_type' => 'IMAGE' })).to eq(type: 'image', image: { id: '9' })
      expect(described_class.parameter({ 'media_id' => '9', 'media_type' => 'document', 'media_name' => 'a.pdf' }))
        .to eq(type: 'document', document: { id: '9', filename: 'a.pdf' })
    end

    it 'devolve nil sem id ou com tipo que não é de topo' do
      expect(described_class.parameter({ 'media_url' => 'https://x.com/a.png', 'media_type' => 'image' })).to be_nil
      expect(described_class.parameter({ 'media_id' => '9', 'media_type' => 'sticker' })).to be_nil
    end
  end
end

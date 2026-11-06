require 'rails_helper'

# Mídia do post (#2198 PR 3, #2653): sobe uma vez, vale para as duas redes por um dia, só nesta conta. O Instagram só
# aceita foto JPEG, então PNG vira JPEG.
RSpec.describe Crm::MetaAds::Creation::PostMedia do
  let(:account) { create(:account) }
  let(:service) { described_class.new(account) }

  def upload(name, type)
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', name), type)
  end

  around { |example| with_modified_env(FRONTEND_URL: 'https://app.example.com') { example.run } }

  it 'foto JPEG: guarda como está e devolve um id que acha o endereço da foto' do
    media = nil
    expect { media = service.upload!(upload('booking_small.jpg', 'image/jpeg')) }.to change(ActiveStorage::Blob, :count).by(1)

    expect(media[:kind]).to eq('image')
    expect(service.find!(media[:signed_id])).to include(kind: 'image', url: start_with('http'))
  end

  it 'foto PNG: vira JPEG antes de guardar' do
    converted = Tempfile.new(['post', '.jpg'], binmode: true)
    converted.write(File.binread(Rails.root.join('spec/assets/booking_small.jpg')))
    converted.rewind
    # A conversão é da libvips (a mesma do Dockerfile); aqui só importa que o PNG não chega à Meta como PNG.
    allow(service).to receive(:jpeg).and_return(converted)

    media = service.upload!(upload('avatar.png', 'image/png'))

    expect(ActiveStorage::Blob.find_signed(media[:signed_id], purpose: "meta_ads_post_media_#{account.id}").content_type).to eq('image/jpeg')
    expect(service).to have_received(:jpeg).with(end_with('.png')).once
  end

  it 'PNG com o tipo de JPEG (o navegador mentiu): vira JPEG pelos bytes' do
    converted = Tempfile.new(['post', '.jpg'], binmode: true)
    converted.write(File.binread(Rails.root.join('spec/assets/booking_small.jpg')))
    converted.rewind
    allow(service).to receive(:jpeg).and_return(converted)

    service.upload!(upload('avatar.png', 'image/jpeg'))

    expect(service).to have_received(:jpeg).once
  end

  it 'foto acima de 8 MB (o teto do Instagram): media_too_large, sem guardar' do
    file = upload('booking_small.jpg', 'image/jpeg')
    allow(file).to receive(:size).and_return(8.megabytes + 1)

    expect { service.upload!(file) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('media_too_large') }
      .and(not_change(ActiveStorage::Blob, :count))
  end

  it 'vídeo: guarda e devolve kind video' do
    media = service.upload!(upload('sample.mp4', 'video/mp4'))

    expect(service.find!(media[:signed_id])).to include(kind: 'video')
  end

  it 'arquivo que não é foto nem vídeo: invalid_media, sem guardar' do
    expect { service.upload!(upload('sample.mp4', 'image/png')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('invalid_media') }
      .and(not_change(ActiveStorage::Blob, :count))
  end

  it 'id de outra conta ou vencido: invalid_media' do
    media = described_class.new(create(:account)).upload!(upload('booking_small.jpg', 'image/jpeg'))

    expect { service.find!(media[:signed_id]) }.to raise_error(Crm::MetaAds::Creation::Error) { |error| expect(error.code).to eq('invalid_media') }
  end
end

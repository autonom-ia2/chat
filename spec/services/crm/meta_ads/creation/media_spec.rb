require 'rails_helper'

# Foto e vídeo do celular (#2198, Fluxo 1): a foto vai em base64 para /adimages e volta com o hash; o vídeo fica no nosso
# armazenamento e a Meta o busca pelo endereço (/advideos com file_url). Os limites (JPG ou PNG até 30 MB, MP4 ou MOV até
# 1 GB) são nossos e valem de novo aqui.
RSpec.describe Crm::MetaAds::Creation::Media do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:act) { "act_#{connection.ad_account_id}" }
  let(:json) { { 'Content-Type' => 'application/json' } }

  def upload(name, type)
    Rack::Test::UploadedFile.new(Rails.root.join('spec/assets', name), type)
  end

  it 'foto: sobe em base64 e devolve hash, endereço e tamanho' do
    file = upload('avatar.png', 'image/png')
    image = { hash: 'h1', url: 'https://scontent.example/h1.png', width: 600, height: 400 }
    request = stub_request(:post, meta_graph_url("#{act}/adimages"))
              .with { |req| Rack::Utils.parse_nested_query(req.body)['bytes'] == Base64.strict_encode64(File.binread(file.path)) }
              .to_return(status: 200, body: { images: { 'avatar.png' => image } }.to_json, headers: json)

    expect(described_class.new(connection).upload!(file)).to eq(kind: 'image', hash: 'h1', url: 'https://scontent.example/h1.png', width: 600,
                                                                height: 400)
    expect(request).to have_been_made.once
  end

  it 'vídeo: guarda o arquivo e manda o endereço para a Meta' do
    request = stub_request(:post, meta_graph_url("#{act}/advideos"))
              .with { |req| Rack::Utils.parse_nested_query(req.body)['file_url'].to_s.start_with?('http') }
              .to_return(status: 200, body: { id: '777' }.to_json, headers: json)

    with_modified_env FRONTEND_URL: 'https://app.example.com' do
      expect { expect(described_class.new(connection).upload!(upload('sample.mp4', 'video/mp4'))).to eq(kind: 'video', video_id: '777') }
        .to change(ActiveStorage::Blob, :count).by(1)
    end
    expect(request).to have_been_made.once
  end

  it 'vídeo sem FRONTEND_URL: falha antes de guardar o arquivo, nunca manda endereço de localhost' do
    with_modified_env FRONTEND_URL: '' do
      expect { described_class.new(connection).upload!(upload('sample.mp4', 'video/mp4')) }
        .to raise_error(ArgumentError, 'FRONTEND_URL vazio: o vídeo do anúncio não teria endereço')
        .and(not_change(ActiveStorage::Blob, :count))
    end
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'arquivo que não é foto nem vídeo aceito: recusa sem chamar a Meta' do
    expect { described_class.new(connection).upload!(upload('sample.pdf', 'application/pdf')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_media') }
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'arquivo que diz ser foto mas não é: recusa sem chamar a Meta' do
    expect { described_class.new(connection).upload!(upload('sample.pdf', 'image/png')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('invalid_media') }
    expect(a_request(:post, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'foto acima de 30 MB: recusa' do
    stub_const("#{described_class}::IMAGE_MAX_BYTES", 10)

    expect { described_class.new(connection).upload!(upload('avatar.png', 'image/png')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('media_too_large') }
  end

  it 'Meta fora do ar: meta_unavailable' do
    stub_request(:post, meta_graph_url("#{act}/adimages")).to_return(status: 500, body: meta_graph_error(1).to_json, headers: json)

    expect { described_class.new(connection).upload!(upload('avatar.png', 'image/png')) }
      .to raise_error(Crm::MetaAds::Creation::Error) { |e| expect(e.code).to eq('meta_unavailable') }
  end
end

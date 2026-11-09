require 'rails_helper'

# A foto ou o texto novos (#2778): o criativo novo sai do de agora, só com o que a pessoa trocou.
RSpec.describe Crm::MetaAds::Creation::CreativeChange do
  let(:video_source) do
    { 'object_story_spec' => { 'page_id' => '1', 'video_data' => { 'video_id' => '10', 'image_hash' => 'capa', 'image_url' => 'https://x/c.jpg',
                                                                   'message' => 'Antes', 'call_to_action' => { 'type' => 'LEARN_MORE' } } } }
  end

  it 'diz o tipo: foto, vídeo, ou nil no carrossel e no post impulsionado' do
    expect(described_class.kind_of({ 'link_data' => { 'image_hash' => 'h' } })).to eq('image')
    expect(described_class.kind_of({ 'video_data' => { 'video_id' => '1' } })).to eq('video')
    expect(described_class.kind_of({ 'link_data' => { 'image_hash' => 'h', 'child_attachments' => [{}] } })).to be_nil
    expect(described_class.kind_of(nil)).to be_nil
  end

  it 'vídeo por vídeo: troca o vídeo e a capa, mantém o botão' do
    change = described_class.from_params(text: ' Depois ', media: { kind: 'video', video_id: '20', image_hash: 'capa2' })

    video = JSON.parse(change.creative_params(video_source, name: 'Bolo')[:object_story_spec])['video_data']

    expect(video).to include('video_id' => '20', 'image_hash' => 'capa2', 'message' => 'Depois', 'call_to_action' => { 'type' => 'LEARN_MORE' })
    expect(video).not_to have_key('image_url')
  end

  it 'só o texto: a mídia fica a de agora' do
    params = described_class.from_params(text: 'Depois').creative_params(video_source, name: 'Bolo')

    expect(JSON.parse(params[:object_story_spec])['video_data']).to include('video_id' => '10', 'image_url' => 'https://x/c.jpg')
    expect(params).not_to have_key(:url_tags)
  end

  it 'texto vazio ou longo demais: invalid_params' do
    expect { described_class.from_params(text: ' ') }.to raise_error(Crm::MetaAds::Creation::Error, 'invalid_params')
    expect { described_class.from_params(text: 'a' * 2001) }.to raise_error(Crm::MetaAds::Creation::Error, 'invalid_params')
  end

  it 'carrossel: invalid_creative' do
    carousel = { 'object_story_spec' => { 'link_data' => { 'image_hash' => 'h', 'child_attachments' => [{}] } } }

    expect { described_class.from_params(text: 'Oi').creative_params(carousel, name: 'x') }
      .to raise_error(Crm::MetaAds::Creation::Error, 'invalid_creative')
  end
end

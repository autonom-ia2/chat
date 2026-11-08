require 'rails_helper'

# #2454: de onde vêm as imagens do post para a leitura da foto. Só o endereço da imagem; vídeo vai pela capa.
RSpec.describe Crm::MetaAds::ComentariosIa::Imagens do
  describe '.do_instagram' do
    it 'a foto do post' do
      expect(described_class.do_instagram('media_type' => 'IMAGE', 'media_url' => 'https://cdn.exemplo/1.jpg'))
        .to eq(['https://cdn.exemplo/1.jpg'])
    end

    it 'o vídeo pela capa' do
      dados = { 'media_type' => 'VIDEO', 'media_url' => 'https://cdn.exemplo/v.mp4', 'thumbnail_url' => 'https://cdn.exemplo/capa.jpg' }

      expect(described_class.do_instagram(dados)).to eq(['https://cdn.exemplo/capa.jpg'])
    end

    it 'o carrossel: cada filho, na ordem, com o vídeo pela capa' do
      dados = { 'media_type' => 'CAROUSEL_ALBUM', 'media_url' => 'https://cdn.exemplo/1.jpg',
                'children' => { 'data' => [{ 'media_type' => 'IMAGE', 'media_url' => 'https://cdn.exemplo/1.jpg' },
                                           { 'media_type' => 'VIDEO', 'thumbnail_url' => 'https://cdn.exemplo/2.jpg' },
                                           { 'media_type' => 'IMAGE', 'media_url' => 'https://cdn.exemplo/3.jpg' }] } }

      expect(described_class.do_instagram(dados)).to eq(%w[https://cdn.exemplo/1.jpg https://cdn.exemplo/2.jpg https://cdn.exemplo/3.jpg])
    end

    it 'sem imagem, ou endereço que não é https: nada' do
      expect(described_class.do_instagram({})).to eq([])
      expect(described_class.do_instagram('media_type' => 'VIDEO')).to eq([])
      expect(described_class.do_instagram('media_type' => 'IMAGE', 'media_url' => 'http://cdn.exemplo/1.jpg')).to eq([])
    end
  end

  describe '.do_facebook' do
    def anexo(src) = { 'media' => { 'image' => { 'src' => src } } }

    # Revisão da Agentes IA: proteção contra defeito, como o carrossel do Instagram (até 10).
    it 'no máximo LIMITE imagens, na ordem' do
      anexos = (1..12).map { |indice| anexo("https://fb.exemplo/#{indice}.jpg") }
      dados = { 'attachments' => { 'data' => [{ 'subattachments' => { 'data' => anexos } }] } }

      expect(described_class.do_facebook(dados)).to eq((1..10).map { |indice| "https://fb.exemplo/#{indice}.jpg" })
      expect(described_class::LIMITE).to eq(10)
    end

    it 'a imagem do anexo do post' do
      expect(described_class.do_facebook('attachments' => { 'data' => [anexo('https://fb.exemplo/1.jpg')] }))
        .to eq(['https://fb.exemplo/1.jpg'])
    end

    it 'o álbum: as imagens de dentro do anexo' do
      dados = { 'attachments' => { 'data' => [anexo('https://fb.exemplo/capa.jpg').merge(
        'subattachments' => { 'data' => [anexo('https://fb.exemplo/1.jpg'), anexo('https://fb.exemplo/2.jpg')] }
      )] } }

      expect(described_class.do_facebook(dados)).to eq(%w[https://fb.exemplo/1.jpg https://fb.exemplo/2.jpg])
    end

    it 'sem anexo: a full_picture; sem nada: vazio' do
      expect(described_class.do_facebook('full_picture' => 'https://fb.exemplo/full.jpg')).to eq(['https://fb.exemplo/full.jpg'])
      expect(described_class.do_facebook('message' => 'Só texto')).to eq([])
    end
  end
end

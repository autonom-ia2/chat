require 'rails_helper'

# Foto do anúncio guardada do clique para o WhatsApp (#1960): o link da Meta expira em poucos dias.
RSpec.describe Crm::MetaAds::ReferralImageJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:ad_id) { '120254710362980416' }
  let(:url) { 'https://scontent.fsdu20-1.fna.fbcdn.net/v/t45.1600-4/anuncio.jpg?oe=6ADD22FC' }
  let(:click) { { 'source' => 'meta_ctwa', 'source_id' => ad_id } }

  describe '.enqueue_for' do
    before { account.enable_features!('anuncios_sem_login') }

    it 'enfileira a foto do anúncio que ainda não tem foto' do
      expect { described_class.enqueue_for(conversation, click, { image_url: url }) }
        .to have_enqueued_job(described_class).with(account.id, ad_id, url)
    end

    it 'usa a miniatura do anúncio em vídeo' do
      expect { described_class.enqueue_for(conversation, click, { 'thumbnail_url' => url }) }
        .to have_enqueued_job(described_class).with(account.id, ad_id, url)
    end

    it 'não enfileira sem a flag, fora da Meta, sem https ou com a foto já guardada' do
      object = Crm::MetaAdObject.create!(account: account, meta_object_id: '999', object_type: 'ad')
      object.image.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'a.png', content_type: 'image/png')

      expect do
        described_class.enqueue_for(conversation, click, { image_url: 'https://evil.example.com/fbcdn.net/a.jpg' })
        described_class.enqueue_for(conversation, click, { image_url: 'http://scontent.fbcdn.net/a.jpg' })
        described_class.enqueue_for(conversation, click, { image_url: 'https://fbcdn.net@evil.example.com/a.jpg' })
        described_class.enqueue_for(conversation, click.merge('source_id' => '999'), { image_url: url })
        described_class.enqueue_for(conversation, click.merge('source' => 'meta_organic'), { image_url: url })
        account.disable_features!('anuncios_sem_login')
        described_class.enqueue_for(conversation.reload, click, { image_url: url })
      end.not_to have_enqueued_job(described_class)
    end
  end

  describe '#perform' do
    it 'baixa e guarda a foto no anúncio' do
      stub_request(:get, url).to_return(status: 200, body: Rails.root.join('spec/assets/sample.png').read, headers: { 'Content-Type' => 'image/png' })

      described_class.perform_now(account.id, ad_id, url)

      object = Crm::MetaAdObject.find_by(account: account, meta_object_id: ad_id)
      expect(object.object_type).to eq('ad')
      expect(object.image).to be_attached
      expect(object.image.content_type).to eq('image/png')
    end

    it 'não segue redirecionamento, nem guarda SVG ou arquivo grande demais' do
      stub_request(:get, url).to_return(
        { status: 302, headers: { 'Location' => 'http://169.254.169.254/latest' } },
        { status: 200, body: '<svg/>', headers: { 'Content-Type' => 'image/svg+xml' } },
        { status: 200, body: 'x' * (described_class::MAX_BYTES + 1), headers: { 'Content-Type' => 'image/png' } }
      )
      internal = stub_request(:get, 'http://169.254.169.254/latest')

      3.times { described_class.perform_now(account.id, ad_id, url) }

      expect(internal).not_to have_been_requested
      expect(Crm::MetaAdObject.find_by(account: account, meta_object_id: ad_id).image).not_to be_attached
    end

    it 'não guarda o que não é imagem e não falha com link vencido' do
      stub_request(:get, url).to_return({ status: 200, body: '<html>', headers: { 'Content-Type' => 'text/html' } }, { status: 403, body: '' })

      expect { 2.times { described_class.perform_now(account.id, ad_id, url) } }.not_to raise_error
      expect(Crm::MetaAdObject.find_by(account: account, meta_object_id: ad_id).image).not_to be_attached
    end
  end
end

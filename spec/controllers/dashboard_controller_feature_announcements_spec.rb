require 'rails_helper'

# #3148: o anúncio de novidade cadastrado no Super Admin chega ao painel também fora da nuvem do Chatwoot.
RSpec.describe DashboardController do
  describe '#active_feature_announcements' do
    let(:video_url) { 'https://www.youtube.com/watch?v=abc123' }

    it 'devolve só os anúncios de novidade ativos, fora da nuvem do Chatwoot' do
      ativo = PlatformBanner.create!(banner_type: :feature_announcement, title: 'Novo', banner_message: 'Texto', video_url: video_url)
      PlatformBanner.create!(banner_type: :feature_announcement, title: 'Velho', banner_message: 'Texto', video_url: video_url,
                             active: false)
      PlatformBanner.create!(banner_type: :info, banner_message: 'Aviso comum')
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)

      anuncios = described_class.new.send(:active_feature_announcements)

      expect(anuncios.pluck('id')).to eq([ativo.id])
      expect(anuncios.first.keys).to contain_exactly('id', 'title', 'banner_message', 'video_url', 'updated_at')
    end

    it 'mantém os avisos comuns só na nuvem do Chatwoot' do
      PlatformBanner.create!(banner_type: :info, banner_message: 'Aviso comum')
      allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false)

      expect(described_class.new.send(:active_platform_banners)).to eq([])
    end
  end
end

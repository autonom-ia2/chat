require 'rails_helper'

# Resgate da foto do anúncio (#2005): o anúncio que teve clique antes da flag pega o link da mensagem mais nova.
RSpec.describe Crm::MetaAds::ReferralImageBackfillJob do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:ad_id) { '120249905040360621' }
  let(:new_url) { 'https://scontent.fsdu20-1.fna.fbcdn.net/v/anuncio-novo.jpg' }
  let(:old_url) { 'https://scontent.fsdu20-1.fna.fbcdn.net/v/anuncio-velho.jpg' }

  # Post orgânico não traz ctwa_clid; com ele, o clique conta como anúncio.
  def click!(url, at:, anuncio: ad_id, source_type: 'ad', conversa: conversation)
    referral = { 'source_id' => anuncio, 'source_type' => source_type, 'image_url' => url }
    referral['ctwa_clid'] = "clid-#{anuncio}" if source_type == 'ad'
    message = create(:message, conversation: conversa, account: conversa.account, message_type: :incoming, content_attributes: { referral: referral })
    message.update_columns(created_at: at) # rubocop:disable Rails/SkipsModelValidations
  end

  before { account.enable_features!('anuncios_sem_login') }

  it 'enfileira a foto com o link da mensagem mais nova de cada anúncio' do
    click!(old_url, at: 2.days.ago)
    click!(new_url, at: 1.hour.ago)
    click!(new_url, at: 1.hour.ago, anuncio: '777')

    expect { described_class.perform_now }
      .to have_enqueued_job(Crm::MetaAds::ReferralImageJob).with(account.id, ad_id, new_url).exactly(:once)
      .and have_enqueued_job(Crm::MetaAds::ReferralImageJob).with(account.id, '777', new_url).exactly(:once)
  end

  it 'usa o link mais novo que é da Meta quando o último clique trouxe outro endereço' do
    click!(old_url, at: 2.days.ago)
    click!('https://evil.example.com/a.jpg', at: 1.hour.ago)

    expect { described_class.perform_now }.to have_enqueued_job(Crm::MetaAds::ReferralImageJob).with(account.id, ad_id, old_url).exactly(:once)
  end

  it 'pula o anúncio que já tem foto' do
    object = Crm::MetaAdObject.create!(account: account, meta_object_id: ad_id, object_type: 'ad')
    object.image.attach(io: Rails.root.join('spec/assets/sample.png').open, filename: 'a.png', content_type: 'image/png')
    click!(new_url, at: 1.hour.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end

  it 'pula o clique mais velho que a janela, mesmo em conversa ativa' do
    click!(new_url, at: 5.days.ago)
    conversation.update_columns(last_activity_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end

  it 'pula post orgânico' do
    click!(new_url, at: 1.hour.ago, source_type: 'post')

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end

  it 'pula link fora da Meta' do
    click!('https://evil.example.com/a.jpg', at: 1.hour.ago)

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end

  it 'pula conta sem a flag' do
    click!(new_url, at: 1.hour.ago, conversa: create(:conversation, account: create(:account)))

    expect { described_class.perform_now }.not_to have_enqueued_job(Crm::MetaAds::ReferralImageJob)
  end
end

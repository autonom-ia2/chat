require 'rails_helper'

RSpec.describe Crm::MetaAdsCommentCare do
  let(:account) { create(:account) }

  it 'cuida de um post ou anúncio uma vez só por conta' do
    create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '179')
    repetido = build(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '179')

    expect(repetido).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, target_kind: 'post', target_id: '179')).to be_valid
  end

  it 'recusa valores fora das listas' do
    expect(build(:crm_meta_ads_comment_care, account: account, target_kind: 'story')).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, network: 'tiktok')).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, status: 'off')).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, handoff: 'robo')).not_to be_valid
  end

  it 'exige a mensagem do privado dentro do limite do Instagram' do
    expect(build(:crm_meta_ads_comment_care, account: account, message: '')).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, message: 'a' * 1001)).not_to be_valid
  end

  it 'exige de uma a três frases públicas curtas' do
    expect(build(:crm_meta_ads_comment_care, account: account, phrases: [])).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, phrases: %w[a b c d])).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, phrases: ['a' * 301])).not_to be_valid
  end

  it 'aceita só botão que abre o WhatsApp' do
    botao = ->(url) { build(:crm_meta_ads_comment_care, account: account, button: { 'title' => 'Chamar', 'url' => url }) }

    expect(botao.call('https://wa.me/5511999990000')).to be_valid
    expect(botao.call('https://golpe.example/wa.me')).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, button: { 'url' => 'https://wa.me/55' })).not_to be_valid
    expect(build(:crm_meta_ads_comment_care, account: account, button: nil)).to be_valid
  end

  describe '#resposta_publica' do
    let(:care) { build(:crm_meta_ads_comment_care, account: account) }

    it 'reveza as frases, sem repetir em seguida' do
      expect((0..3).map { |vez| care.resposta_publica('private', vez) })
        .to eq(['Te chamei no privado 😊', 'Te mandei os detalhes no privado!', 'Olha o seu privado 💬', 'Te chamei no privado 😊'])
    end

    it 'responde o preço só com a chave do preço ligada' do
      expect(care.resposta_publica('price', 0)).to eq('A partir de R$ 490 😊 Te mandei os detalhes no privado.')

      care.price_reply = nil
      expect(care.resposta_publica('price', 0)).to eq('Te chamei no privado 😊')
    end
  end

  it 'lê a ficha sem oferta como post que não vende' do
    care = build(:crm_meta_ads_comment_care, account: account, offer: nil)

    expect(care.offer?).to be(false)
    expect(build(:crm_meta_ads_comment_care, account: account).offer?).to be(true)
  end

  it 'manda privado só com a ficha da oferta ou com o "para quem" do dono' do
    expect(build(:crm_meta_ads_comment_care, account: account).privado?).to be(true)
    expect(build(:crm_meta_ads_comment_care, account: account, offer: nil).privado?).to be(false)
    expect(build(:crm_meta_ads_comment_care, account: account, offer: nil, para_quem: 'Quem pedir o link').privado?).to be(true)
  end

  it 'limita o "para quem" do dono' do
    expect(build(:crm_meta_ads_comment_care, account: account, para_quem: 'a' * 501)).not_to be_valid
  end

  it 'separa os cuidados ativos dos pausados' do
    ativo = create(:crm_meta_ads_comment_care, account: account)
    create(:crm_meta_ads_comment_care, account: account, status: 'paused')

    expect(described_class.on).to contain_exactly(ativo)
  end

  describe '.cuidando' do
    let!(:post) { create(:crm_meta_ads_comment_care, account: account, target_kind: 'post', target_id: '179') }
    let!(:anuncio) { create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120') }

    it 'acha o cuidado do post do comentário' do
      expect(described_class.cuidando(network: 'instagram', account_id: account.id, post_id: '179', ad_id: nil)).to eq(post)
    end

    it 'prefere o cuidado do anúncio quando o comentário veio dele' do
      expect(described_class.cuidando(network: 'instagram', account_id: account.id, post_id: '179', ad_id: '120')).to eq(anuncio)
    end

    it 'acha o anúncio pelo post do criativo quando o comentário chega sem o id do anúncio' do
      anuncio.update!(post_ids: %w[555_888 17900])

      expect(described_class.cuidando(network: 'instagram', account_id: account.id, post_id: '555_888', ad_id: nil)).to eq(anuncio)
      expect(described_class.cuidando(network: 'instagram', account_id: account.id, post_id: '555_999', ad_id: nil)).to be_nil
    end

    it 'só vale na rede do cuidado; o anúncio das duas redes vale nas duas' do
      expect(described_class.cuidando(network: 'facebook', account_id: account.id, post_id: '179', ad_id: nil)).to be_nil

      anuncio.update!(network: 'both')
      expect(described_class.cuidando(network: 'facebook', account_id: account.id, post_id: nil, ad_id: '120')).to eq(anuncio)
    end

    it 'ignora cuidado pausado e de outra conta' do
      post.update!(status: 'paused')

      expect(described_class.cuidando(network: 'instagram', account_id: account.id, post_id: '179', ad_id: nil)).to be_nil
      expect(described_class.cuidando(network: 'instagram', account_id: create(:account).id, post_id: '179', ad_id: nil)).to be_nil
    end
  end
end

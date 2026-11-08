require 'rails_helper'

RSpec.describe Crm::MetaAds::ComentariosIa::CuidarJob do
  let(:account) { create(:account) }
  let(:dados) do
    { 'network' => 'instagram', 'account_id' => account.id, 'inbox_id' => 1, 'owner_id' => 'ig-1', 'post_id' => '1790',
      'ad_id' => nil, 'comment_id' => 'c-1', 'parent_id' => nil, 'from_id' => 'igsid-1', 'created_time' => '2026-10-27T10:00:00Z' }
  end
  let(:cuidar) { instance_double(Crm::MetaAds::ComentariosIa::Cuidar) }

  before { allow(Crm::MetaAds::ComentariosIa::Cuidar).to receive(:new).and_return(cuidar) }

  it 'cuida do comentário' do
    allow(cuidar).to receive(:call)

    described_class.perform_now(dados)

    expect(Crm::MetaAds::ComentariosIa::Cuidar).to have_received(:new).with(an_object_having_attributes(comment_id: 'c-1'))
    expect(cuidar).to have_received(:call)
  end

  {
    'a Meta não responde à leitura do comentário' => Crm::MetaAds::ComentariosIa::Rede::Indisponivel,
    'a IA não responde à pergunta' => Crm::MetaAds::ComentariosIa::Classificador::Indisponivel.new('ai_timeout')
  }.each do |caso, erro|
    describe caso do
      before { allow(cuidar).to receive(:call).and_raise(erro) }

      it 'tenta de novo mais tarde' do
        expect { described_class.perform_now(dados) }.to have_enqueued_job(described_class).with(dados)
        expect(Crm::MetaAdsCommentAction.count).to eq(0)
      end

      it 'esgotadas as tentativas: o comentário fica com a pessoa ("não consegui ler"), com aviso só com ids, e não volta' do
        allow(Rails.logger).to receive(:warn)

        perform_enqueued_jobs { described_class.perform_later(dados) }

        expect(cuidar).to have_received(:call).exactly(described_class::TENTATIVAS).times
        expect(Crm::MetaAdsCommentAction.where(account_id: account.id, comment_id: 'c-1', actor: 'ai').pluck(:action))
          .to contain_exactly('ai_seen', 'ai_unread')
        expect(Rails.logger).to have_received(:warn).with(include('comment=c-1'))
        expect(enqueued_jobs).to be_empty
      end
    end
  end

  # #2519: o "não cuidei" da queda é gravado como o Cuidar grava, para o Esperando contar o mesmo por anúncio.
  describe 'esgotado: o anúncio nas linhas (Cuidar.registrado)' do
    before { allow(cuidar).to receive(:call).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel) }

    it 'no Facebook, com o cuidado de um anúncio: as linhas levam o anúncio, e o Esperando conta' do
      create(:crm_meta_ads_comment_care, account: account, target_kind: 'ad', target_id: '120', network: 'both', post_ids: %w[555_1790])

      perform_enqueued_jobs { described_class.perform_later(dados.merge('network' => 'facebook', 'post_id' => '555_1790')) }

      expect(Crm::MetaAdsCommentAction.where(comment_id: 'c-1').pluck(:action, :ad_id)).to contain_exactly(%w[ai_seen 120], %w[ai_unread 120])
      expect(Crm::MetaAds::ComentariosIa::Esperando.por_anuncio(account.id, %w[120])).to eq('120' => 1)
    end

    it 'a resposta dentro de um comentário vai sem anúncio (só o primeiro nível conta)' do
      perform_enqueued_jobs { described_class.perform_later(dados.merge('ad_id' => '120', 'parent_id' => 'c-0')) }

      expect(Crm::MetaAdsCommentAction.where(comment_id: 'c-1').pluck(:ad_id).uniq).to eq([nil])
    end
  end

  it 'esgotado depois de limites da Meta no privado: a pessoa reservada por este comentário fica livre' do
    allow(cuidar).to receive(:call).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    Crm::MetaAdsCommentPerson.create!(account: account, network: 'instagram', post_id: '1790', from_id: 'igsid-1', comment_id: 'c-1')
    Crm::MetaAdsCommentPerson.create!(account: account, network: 'instagram', post_id: '1790', from_id: 'igsid-2', comment_id: 'c-9')

    perform_enqueued_jobs { described_class.perform_later(dados) }

    expect(Crm::MetaAdsCommentPerson.pluck(:comment_id)).to eq(['c-9'])
  end

  it 'esgotado, mas outro job já reservou o comentário: não grava o "não consegui ler" por cima' do
    allow(cuidar).to receive(:call).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel)
    allow(Crm::MetaAds::ComentariosIa::Registro).to receive(:reservar!).and_return(false)
    allow(Crm::MetaAds::ComentariosIa::Registro).to receive(:gravar!)

    perform_enqueued_jobs { described_class.perform_later(dados) }

    expect(Crm::MetaAds::ComentariosIa::Registro).not_to have_received(:gravar!)
  end
end

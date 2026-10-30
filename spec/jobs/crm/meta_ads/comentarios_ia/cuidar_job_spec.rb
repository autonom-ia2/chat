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

  describe 'a Meta não responde à leitura do comentário' do
    before { allow(cuidar).to receive(:call).and_raise(Crm::MetaAds::ComentariosIa::Rede::Indisponivel) }

    it 'tenta de novo mais tarde' do
      expect { described_class.perform_now(dados) }.to have_enqueued_job(described_class).with(dados)
      expect(Crm::MetaAdsCommentAction.count).to eq(0)
    end

    it 'esgotadas as tentativas: o comentário fica descartado (lido pela IA), com aviso só com ids, e não volta à fila' do
      allow(Rails.logger).to receive(:warn)

      perform_enqueued_jobs { described_class.perform_later(dados) }

      expect(cuidar).to have_received(:call).exactly(described_class::TENTATIVAS).times
      expect(Crm::MetaAdsCommentAction.sole).to have_attributes(account_id: account.id, comment_id: 'c-1', action: 'ai_seen', actor: 'ai')
      expect(Rails.logger).to have_received(:warn).with(include('comment=c-1'))
      expect(enqueued_jobs).to be_empty
    end
  end
end

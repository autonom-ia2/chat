require 'rails_helper'

# A trava do mesmo pedido (#2198): só uma tentativa que ainda pode ter campanha viva por pedido, conta e conta de anúncios.
RSpec.describe Crm::MetaAdsCreatedObject do
  let(:account) { create(:account) }
  let(:digest) { 'a' * 64 }

  def attempt(status, account: self.account, ad_account_id: '111')
    described_class.create!(account: account, idempotency_key: SecureRandom.uuid, status: status, ad_account_id: ad_account_id,
                            request_digest: digest)
  end

  it 'duas tentativas vivas do mesmo pedido não coexistem, nem no mesmo instante' do
    attempt('unconfirmed')

    %w[creating unconfirmed rollback_failed].each do |status|
      expect { attempt(status) }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it 'tentativa encerrada (criada ou desfeita) não trava; outra conta ou conta de anúncios também não' do
    attempt('created')
    attempt('rolled_back')
    attempt('creating')

    expect { attempt('creating', account: create(:account)) }.not_to raise_error
    expect { attempt('creating', ad_account_id: '222') }.not_to raise_error
  end

  # #2522: o post de origem do anúncio que impulsionou um post por aqui.
  describe '.ads_by_post' do
    def boosted(post_id, ad_id, **attributes)
      described_class.create!({ account: account, idempotency_key: SecureRandom.uuid, status: 'created', ad_id: ad_id,
                                source_post_id: post_id, source_post_network: 'instagram', activated_at: 1.day.ago }.merge(attributes))
    end

    it 'devolve os anúncios ativados de cada post, o mais novo primeiro' do
      boosted('1790', '901', activated_at: 2.days.ago)
      boosted('1790', '902', activated_at: 1.hour.ago)
      boosted('1791', '903')

      expect(described_class.ads_by_post(account.id, 'instagram', %w[1790 1791 1792]))
        .to eq('1790' => %w[902 901], '1791' => %w[903])
    end

    it 'pausado sem nunca rodar, não criado, de outra rede ou de outra conta não conta' do
      boosted('1790', '901', activated_at: nil)
      boosted('1790', '902', status: 'rolled_back')
      boosted('1790', '903', source_post_network: 'facebook')
      boosted('1790', '904', account: create(:account))

      expect(described_class.ads_by_post(account.id, 'instagram', ['1790'])).to eq({})
    end

    it 'sem posts, nem consulta' do
      expect(described_class.ads_by_post(account.id, 'instagram', [])).to eq({})
    end
  end
end

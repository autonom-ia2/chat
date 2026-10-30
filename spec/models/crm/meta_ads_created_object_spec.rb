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
end

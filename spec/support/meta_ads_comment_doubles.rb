# Peças do épico #2194 em volta dos comentários do Facebook (#2197). A Página da conta é a tabela real
# (Crm::MetaAdsPage, #2195) e as ações vão para Crm::MetaAdsCommentAction (#2196); a assinatura do feed não sai para a
# Meta (Crm::MetaAds::PageSubscription, #2200, tem specs próprios).
module MetaAdsCommentDoubles
  # Devolve a Página da conta, que o spec pode ajustar.
  def simulate_meta_ads_comment_pieces(account:, page_id:, feed_receiving: true)
    allow(Crm::MetaAds::PageSubscription).to receive(:new).and_return(instance_double(Crm::MetaAds::PageSubscription, add!: true))
    Crm::MetaAdsPage.create!(account: account, page_id: page_id, feed_receiving: feed_receiving)
  end
end

RSpec.configure do |config|
  config.include MetaAdsCommentDoubles
end

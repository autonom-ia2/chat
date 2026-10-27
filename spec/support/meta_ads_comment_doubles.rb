# Peças de outros PRs do épico #2194 que os comentários do Facebook (#2197) usam e que ainda não estão na main:
# Crm::MetaAdsPage (#2195), Crm::MetaAdsCommentAction (#2196) e Crm::MetaAds::PageSubscription (infra #2200).
# Cada spec do #2197 chama `simulate_meta_ads_comment_pieces`; quando a peça chegar à main, o stub dela sai daqui.
module MetaAdsCommentDoubles
  def simulate_meta_ads_comment_pieces(account_ids: [])
    pages = Module.new do
      def self.account_ids_for(_page_id) = []
      def self.remember!(_account, _pages) = []
    end
    stub_const('Crm::MetaAdsPage', pages) unless defined?(Crm::MetaAdsPage)
    allow(Crm::MetaAdsPage).to receive_messages(account_ids_for: account_ids, remember!: [])
    stub_const('Crm::MetaAdsCommentAction', Module.new { def self.record!(**) = true }) unless defined?(Crm::MetaAdsCommentAction)
    allow(Crm::MetaAdsCommentAction).to receive(:record!)
    simulate_page_subscription
  end

  def simulate_page_subscription
    return if defined?(Crm::MetaAds::PageSubscription)

    stub_const('Crm::MetaAds::PageSubscription', Class.new do
      def initialize(**); end
      def add!(_fields) = true
    end)
  end
end

RSpec.configure do |config|
  config.include MetaAdsCommentDoubles
end

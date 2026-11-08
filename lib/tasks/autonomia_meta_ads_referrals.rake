# Assina `messaging_referrals` nas Páginas do Messenger criadas antes do #2521 (o anúncio de clique para o Messenger
# chega por esse campo). Uma Página por vez, em job (Crm::MetaAds::MessagingReferralsSubscribeJob): a escrita na
# Página pode levar até ~50 s.
#
#   bundle exec rails autonomia:meta_ads:assinar_referrals                 # DRY_RUN (padrão): só lista
#   APPLY=true bundle exec rails autonomia:meta_ads:assinar_referrals      # enfileira
#   APPLY=true ACCOUNT_IDS=16,18 bundle exec rails autonomia:meta_ads:assinar_referrals
#
# Escreve na Meta, nas Páginas dos clientes: APPLY só com o OK do Rodrigo. Uma stack por vez: a trava da escrita na
# Página (Crm::MetaAds::PageSubscription) vale dentro de uma stack só.
namespace :autonomia do
  namespace :meta_ads do
    desc 'Assina messaging_referrals nas Páginas do Messenger já conectadas (DRY_RUN padrão; APPLY=true enfileira)'
    task assinar_referrals: :environment do
      apply = ENV['APPLY'] == 'true'
      account_ids = ENV['ACCOUNT_IDS'].to_s.split(',').map(&:strip).compact_blank.map(&:to_i)
      scope = Channel::FacebookPage.order(:id)
      scope = scope.where(account_id: account_ids) if account_ids.any?
      # Uma escrita por Página: a mesma Página pode ser caixa de mais de uma conta (o job tenta o token de cada uma).
      pages = scope.reject(&:reauthorization_required?).uniq(&:page_id)

      puts "[meta_ads][assinar_referrals] mode=#{apply ? 'APPLY' : 'DRY_RUN'} pages=#{pages.size}"
      pages.each { |page| puts "[meta_ads][assinar_referrals] account=#{page.account_id} channel=#{page.id} page=#{page.page_id}" }
      next puts('[meta_ads][assinar_referrals] DRY_RUN: nada enfileirado. Rode de novo com APPLY=true.') unless apply

      # Com ACCOUNT_IDS, o job só usa o token das caixas dessas contas.
      pages.each { |page| Crm::MetaAds::MessagingReferralsSubscribeJob.perform_later(page.page_id, account_ids: account_ids.presence) }
      puts "[meta_ads][assinar_referrals] enfileirados=#{pages.size}"
    end
  end
end

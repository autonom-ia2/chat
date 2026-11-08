# Resgate da foto do anúncio (#2005). O ReferralImageJob guarda a foto no clique, mas só a partir do clique seguinte
# à flag `anuncios_sem_login`: o anúncio que já tinha conversas e não teve clique novo ficava sem foto, embora o link
# esteja guardado na mensagem do clique (content_attributes.referral). O link da Meta vence em ~4 dias, então só a
# mensagem mais nova de cada anúncio, dentro de WINDOW, serve. Link vencido não é erro (o ReferralImageJob registra e
# segue); o próximo clique no anúncio traz um link novo.
class Crm::MetaAds::ReferralImageBackfillJob < ApplicationJob
  queue_as :scheduled_jobs

  WINDOW = 4.days

  def perform
    Account.find_each do |account|
      backfill(account) if Crm::MetaAds::SemLogin.enabled?(account)
    end
  end

  private

  def backfill(account)
    newest_urls(account).each do |ad_id, url|
      next if Crm::MetaAds::ReferralImageJob.stored?(account.id, ad_id)

      Crm::MetaAds::ReferralImageJob.perform_later(account.id, ad_id, url)
    end
  end

  # { id do anúncio => link da foto da mensagem mais nova }, só cliques para o WhatsApp. Lê em lotes as mensagens que
  # chegaram na janela (índice account_id + created_at + message_type) e guarda, por anúncio, o link mais novo.
  def newest_urls(account)
    newest = {}
    account.messages.incoming.where(created_at: WINDOW.ago..).select(:id, :created_at, :content_attributes).find_each do |message|
      ad_id, url = ad_image(message)
      next if url.nil? || (newest[ad_id] && newest[ad_id][:at] >= message.created_at)

      newest[ad_id] = { at: message.created_at, url: url }
    end
    newest.transform_values { |row| row[:url] }
  end

  def ad_image(message)
    referral = message.content_attributes.to_h.stringify_keys['referral']
    touch = Ctwa::CampaignBuilder.build(referral)
    return unless touch && touch['source'] == Ctwa::CampaignBuilder::CTWA_SOURCE && touch['source_id'].present?

    [touch['source_id'].to_s, Crm::MetaAds::ReferralImageJob.image_url(referral)]
  end
end

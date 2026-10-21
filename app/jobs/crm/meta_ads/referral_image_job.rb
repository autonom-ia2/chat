# Guarda a foto do anúncio que veio no clique para o WhatsApp (#1960). O referral do clique traz `image_url` (ou
# `thumbnail_url`, no anúncio em vídeo) num endereço da Meta que expira em poucos dias (medido em 20/10/2026: ~4
# dias), então a foto é baixada uma vez por anúncio e fica em Crm::MetaAdObject#image. O anúncio que já tem foto
# não baixa de novo.
#
# Só endereço https da Meta (fbcdn.net, cdninstagram.com), sem seguir redirecionamento (o host conferido é o que
# responde), até MAX_BYTES e só foto comum (IMAGE_TYPES; SVG fica de fora). Link vencido ou recusado não é erro: o
# próximo clique no mesmo anúncio traz um link novo. O endereço não vai para o log (é assinado).
class Crm::MetaAds::ReferralImageJob < ApplicationJob
  queue_as :low

  MAX_BYTES = 5.megabytes
  META_HOSTS = %w[fbcdn.net cdninstagram.com].freeze
  IMAGE_TYPES = %w[image/jpeg image/png image/webp image/gif].freeze

  def self.enqueue_for(conversation, touch, referral)
    return unless touch['source'] == Ctwa::CampaignBuilder::CTWA_SOURCE && touch['source_id'].present?

    url = image_url(referral)
    return if url.nil? || !Crm::MetaAds::SemLogin.enabled?(conversation.account_id)
    return if stored?(conversation.account_id, touch['source_id'].to_s)

    perform_later(conversation.account_id, touch['source_id'].to_s, url)
  end

  def self.image_url(referral)
    ref = referral.to_h.stringify_keys
    url = (ref['image_url'].presence || ref['thumbnail_url'].presence).to_s.strip
    meta_cdn?(url) ? url : nil
  end

  def self.meta_cdn?(url)
    uri = URI.parse(url)
    host = uri.host.to_s
    uri.is_a?(URI::HTTPS) && uri.userinfo.nil? && META_HOSTS.any? { |meta| host == meta || host.end_with?(".#{meta}") }
  rescue URI::InvalidURIError
    false
  end

  def self.stored?(account_id, ad_id)
    Crm::MetaAdObject.where(account_id: account_id, meta_object_id: ad_id).joins(:image_attachment).exists?
  end

  def perform(account_id, ad_id, url)
    object = ad_object(account_id, ad_id)
    return if object.image.attached?

    file = Down.download(url, max_size: MAX_BYTES, max_redirects: 0)
    return unless IMAGE_TYPES.include?(file.content_type.to_s)

    object.image.attach(io: file, filename: "anuncio-#{ad_id}#{File.extname(file.original_filename.to_s)}", content_type: file.content_type)
  rescue Down::Error => e
    Rails.logger.info("Crm::MetaAds::ReferralImageJob no image account=#{account_id} ad=#{ad_id}: #{e.class.name}")
  end

  private

  def ad_object(account_id, ad_id)
    Crm::MetaAdObject.find_or_create_by!(account_id: account_id, meta_object_id: ad_id) { |row| row.object_type = 'ad' }
  rescue ActiveRecord::RecordNotUnique
    Crm::MetaAdObject.find_by!(account_id: account_id, meta_object_id: ad_id)
  end
end

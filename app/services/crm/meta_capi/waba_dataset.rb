# Where a WhatsApp sale event goes (#1940): the dataset of the WABA of the inbox the
# click came through, never a dataset typed per funnel. A funnel can be fed by two
# official inboxes (two WABAs), and each needs its own dataset.
#
# The id is kept in the channel's provider_config ('meta_dataset') together with the WABA
# it belongs to, so Meta is asked once per inbox and a reauthorization onto another WABA
# looks it up again instead of reusing the old one. Written straight in SQL on purpose:
# saving the channel normally re-validates the provider config against Meta, and a jsonb
# merge does not lose a concurrent write to another key. Failing to keep it only costs a
# lookup next time, so it never fails the send.
#
# A passing lookup failure raises LookupError (the caller retries). A dead token or a
# missing permission raises AccessDenied (the inbox must be reconnected). Any other failure
# that would repeat (bad WABA id, odd answer) and an answer without a dataset return nil:
# retrying would not help.
module Crm::MetaCapi::WabaDataset
  module_function

  CONFIG_KEY = 'meta_dataset'.freeze

  class LookupError < StandardError; end
  class AccessDenied < StandardError; end

  def for(channel, access_token:, waba_id:)
    cached = cached_id(channel, waba_id)
    return cached if cached

    result = Meta::WabaDatasetClient.new(access_token: access_token, waba_id: waba_id).find_or_create
    raise_on_failure!(result)
    return log_unavailable(channel, result.error) if result.dataset_id.blank?

    remember(channel, waba_id, result.dataset_id)
    result.dataset_id
  end

  def cached_id(channel, waba_id)
    cached = channel.provider_config.to_h[CONFIG_KEY]
    cached['id'].presence if cached.is_a?(Hash) && cached['waba_id'].to_s == waba_id.to_s
  end

  def raise_on_failure!(result)
    raise LookupError, result.error if result.error.present? && result.transient
    raise AccessDenied, result.error if result.access_denied
  end

  def log_unavailable(channel, error)
    Rails.logger.warn("Crm::MetaCapi::WabaDataset no dataset channel=#{channel.id}: #{error.presence || 'empty answer'}")
    nil
  end

  def remember(channel, waba_id, dataset_id)
    channel.class.where(id: channel.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["provider_config = COALESCE(provider_config, '{}'::jsonb) || " \
       "jsonb_build_object(?::text, jsonb_build_object('waba_id', ?::text, 'id', ?::text))",
       CONFIG_KEY, waba_id.to_s, dataset_id]
    )
  rescue StandardError => e
    Rails.logger.warn("Crm::MetaCapi::WabaDataset could not keep dataset channel=#{channel.id}: #{e.class.name}")
  end
end

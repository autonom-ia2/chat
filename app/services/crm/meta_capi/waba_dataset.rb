# Where a WhatsApp sale event goes (#1940): the dataset of the WABA of the inbox the
# click came through, never a dataset typed per funnel. A funnel can be fed by two
# official inboxes (two WABAs), and each needs its own dataset.
#
# The id is kept in the channel's provider_config ('meta_dataset') together with the WABA
# it belongs to, so Meta is asked once per inbox and a reauthorization onto another WABA
# looks it up again instead of reusing the old one. Written straight in SQL on purpose:
# saving the channel normally re-validates the provider config against Meta, and a jsonb
# merge does not lose a concurrent write to another key.
#
# A failed lookup raises LookupError (the caller retries); nil only when Meta answered
# without a dataset.
module Crm::MetaCapi::WabaDataset
  module_function

  CONFIG_KEY = 'meta_dataset'.freeze

  class LookupError < StandardError; end

  def for(channel, access_token:, waba_id:)
    cached = channel.provider_config.to_h[CONFIG_KEY]
    return cached['id'] if cached.is_a?(Hash) && cached['waba_id'].to_s == waba_id.to_s && cached['id'].present?

    result = Meta::WabaDatasetClient.new(access_token: access_token, waba_id: waba_id).find_or_create
    raise LookupError, result.error if result.error.present?
    return if result.dataset_id.blank?

    remember(channel, waba_id, result.dataset_id)
    result.dataset_id
  end

  def remember(channel, waba_id, dataset_id)
    channel.class.where(id: channel.id).update_all( # rubocop:disable Rails/SkipsModelValidations
      ["provider_config = COALESCE(provider_config, '{}'::jsonb) || " \
       "jsonb_build_object(?::text, jsonb_build_object('waba_id', ?::text, 'id', ?::text))",
       CONFIG_KEY, waba_id.to_s, dataset_id]
    )
  end
end

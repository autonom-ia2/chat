# State of one "Ajustar com IA" request (#1095), kept in Redis like Crm::Ai::InteractiveRequest: the e-mail
# as it was on the screen (base), what the request needs for a second round, and the outcome the editor
# shows before anything changes — the adjusted MJML (proposed), the model's sentence when the request
# cannot be done (refused) or the quality check that still failed (failed). Never written to the
# campaign: the person applies it, or not, in the editor. Every read is bound to the generation token,
# so a newer generation hides an older adjustment.
class EmailCampaigns::Ai::Adjustment
  TTL = 1.day
  PREFIX = 'email_campaigns:ai:adjustment:'.freeze

  # request: { base:, placeholders:, instructions:, input:, brand_identity: } — the e-mail before (canonical MJML), what
  # a second round needs to ask again and the identity the adjustment used (#1111: with the notice about a site
  # asked for in the request).
  def self.start(campaign, token:, request:)
    data = request.to_h.stringify_keys.slice('base', 'placeholders', 'instructions', 'input', 'brand_identity')
                  .merge('token' => token, 'round' => 0, 'status' => 'working')
    data['placeholders'] = Array(data['placeholders'])
    Redis::Alfred.set(key(campaign), data.to_json, ex: TTL.to_i)
  end

  # The adjustment of the generation `token`, or nil.
  def self.find(campaign, token)
    return nil if token.blank?

    value = Redis::Alfred.get(key(campaign))
    data = value.present? ? JSON.parse(value) : nil
    data if data && data['token'] == token
  end

  def self.update(campaign, token, changes)
    data = find(campaign, token)
    return false if data.nil?

    # KEEPTTL: an update never brings an expired adjustment back.
    Redis::Alfred.with { |conn| conn.set(key(campaign), data.merge(changes.stringify_keys).to_json, xx: true, keepttl: true) }
  end

  def self.clear(campaign)
    Redis::Alfred.delete(key(campaign))
  end

  # The person applied the proposal in the editor. Only a proposal of the current generation counts, and only an
  # adjustment that used a site asked for in the request (#1111) changes the identity the campaign records; a
  # discarded proposal (clear) never writes. The proposal is used up either way. -> the campaign's brand_identity.
  def self.apply(campaign)
    data = find(campaign, campaign.ai_generation_token)
    identity = data && data['status'] == 'proposed' ? data['brand_identity'].to_h : {}
    change_identity(campaign, identity) if identity.dig('site_request', 'status') == 'used'
    clear(campaign)
    campaign.brand_identity
  end

  # "Desfazer" right after applying: the identity the campaign had before comes back, once, while the generation is
  # still the one that applied it. -> the campaign's brand_identity.
  def self.undo(campaign)
    value = Redis::Alfred.get(undo_key(campaign))
    # The delete is the claim: of two clicks only the one that removed the key restores (single use).
    data = value.present? && Redis::Alfred.delete(undo_key(campaign)).to_i == 1 ? JSON.parse(value) : nil
    same_generation = data && data['token'].present? && data['token'] == campaign.ai_generation_token
    campaign.record_brand_identity!(data['previous'].to_h) if same_generation
    campaign.brand_identity
  end

  def self.change_identity(campaign, identity)
    undo = { 'token' => campaign.ai_generation_token, 'previous' => campaign.brand_identity.to_h }
    Redis::Alfred.set(undo_key(campaign), undo.to_json, ex: TTL.to_i)
    campaign.record_brand_identity!(identity)
  end
  private_class_method :change_identity

  def self.undo_key(campaign)
    "#{key(campaign)}:undo"
  end

  # Each provider response is handled once, even if Sidekiq delivers the poll twice.
  def self.claim_response(campaign, response_id)
    Redis::Alfred.set("#{key(campaign)}:#{response_id}", '1', nx: true, ex: TTL.to_i)
  end

  # What the editor needs: never the inputs of the request, and the before/after only once there is a proposal
  # (the status is polled every few seconds while the model works).
  def self.presented(campaign, token)
    data = find(campaign, token)
    return nil if data.nil?

    return data.slice('status', 'reason', 'problem').compact unless data['status'] == 'proposed'

    data.slice('status', 'base', 'mjml', 'summary').merge('site_request' => data.dig('brand_identity', 'site_request')).compact
  end

  def self.key(campaign)
    "#{PREFIX}#{campaign.id}"
  end
end

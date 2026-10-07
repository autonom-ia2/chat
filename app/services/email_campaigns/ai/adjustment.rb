# State of one "Ajustar com IA" request (#1095), kept in Redis like Crm::Ai::InteractiveRequest: the e-mail
# as it was on the screen (base), what the request needs for a second round, and the outcome the editor
# shows before anything changes — the adjusted MJML (proposed), the model's sentence when the request
# cannot be done (refused) or the quality check that still failed (failed). Never written to the
# campaign: the person applies it, or not, in the editor. Every read is bound to the generation token,
# so a newer generation hides an older adjustment.
class EmailCampaigns::Ai::Adjustment
  TTL = 1.day
  PREFIX = 'email_campaigns:ai:adjustment:'.freeze

  # request: { base:, placeholders:, instructions:, input: } — the e-mail before (canonical MJML) and what a
  # second round needs to ask again.
  def self.start(campaign, token:, request:)
    data = request.to_h.stringify_keys.slice('base', 'placeholders', 'instructions', 'input')
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

  # Each provider response is handled once, even if Sidekiq delivers the poll twice.
  def self.claim_response(campaign, response_id)
    Redis::Alfred.set("#{key(campaign)}:#{response_id}", '1', nx: true, ex: TTL.to_i)
  end

  # What the editor needs: never the inputs of the request, and the before/after only once there is a proposal
  # (the status is polled every few seconds while the model works).
  def self.presented(campaign, token)
    data = find(campaign, token)
    return nil if data.nil?

    fields = data['status'] == 'proposed' ? %w[status base mjml summary] : %w[status reason problem]
    data.slice(*fields).compact
  end

  def self.key(campaign)
    "#{PREFIX}#{campaign.id}"
  end
end

class Autonomia::Agents::MirrorIdentitySync
  def initialize(agent:)
    @agent = agent
  end

  def perform
    kept_links.find_each do |link|
      mirror = link.agent_bot
      next unless mirror.account_id == @agent.account_id && mirror.outgoing_url.nil?

      mirror.update!(name: @agent.name)
      sync_avatar!(mirror)
    end
  end

  private

  def kept_links
    @agent.agent_inboxes.kept.where(account: @agent.account).includes(:agent_bot)
  end

  def sync_avatar!(mirror)
    if @agent.avatar.attached?
      return if mirror.avatar.attached? && mirror.avatar.blob_id == @agent.avatar.blob_id

      mirror.avatar.attach(@agent.avatar.blob)
    elsif mirror.avatar.attached?
      mirror.avatar.purge
    end
  end
end

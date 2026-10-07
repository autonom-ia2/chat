# Which visual identity an AI e-mail uses (#1076), resolved in the job from what the composer sent:
#   { 'kit_id' => 1, 'mode' => 'light' }          a kit of the account (archived after the click still counts)
#   { 'import_id' => 9, 'mode' => 'dark' }        a site read for this e-mail only ("Usar outro site")
#   nil / {}                                     no identity: the model picks colors as before
# A site the person asked for in the request itself (#1111, `requested_url`, found by SiteRequest) wins over all
# of these for this e-mail: it is read now (BrandKits::SiteImporter, same limits) and the reading is kept as a
# BrandImportJob so the editor can save it as an identity (marked result['origin'] = 'briefing': out of the import
# screen's limit, capped at BrandImportJob::BRIEFING_HOURLY_LIMIT per hour, failed reads included). When it cannot be
# read, the identity above is used and the snapshot says so ('site_request' => { host, status: 'unreadable' }).
# Returns [identity, snapshot]: the BrandKits::PromptPayload hash for the prompt (or nil) and what the
# campaign records in brand_identity (Resultado shows it). The logo of a site read for one e-mail is
# stored with the campaign (builder_assets) so the e-mail never points at another host for it; when it
# cannot be stored the e-mail goes without logo.
class EmailCampaigns::Ai::BrandResolution
  BRIEFING_ORIGIN = { 'origin' => BrandImportJob::ORIGIN_BRIEFING }.freeze

  def initialize(campaign, brand, requested_url: nil)
    @campaign = campaign
    @brand = brand.is_a?(Hash) ? brand.stringify_keys : {}
    @mode = BrandKits::EmailPalettes::MODES.include?(@brand['mode']) ? @brand['mode'] : BrandKits::EmailPalettes::DEFAULT_MODE
    @requested_url = requested_url.presence
  end

  def call
    return [nil, {}] unless BrandKits::Config.enabled?
    return from_requested_site if @requested_url

    chosen
  end

  private

  def chosen
    return from_import if @brand['import_id'].present?
    return from_kit if @brand['kit_id'].present?

    [nil, {}]
  end

  def from_kit
    kit = BrandKit.where(account_id: @campaign.account_id).find_by(id: @brand['kit_id'])
    return [nil, {}] if kit.nil?

    [BrandKits::PromptPayload.new(kit, mode: @mode).to_h, { 'kit_id' => kit.id, 'name' => kit.name, 'mode' => @mode, 'source' => 'kit' }]
  end

  def from_import
    import = BrandImportJob.where(account_id: @campaign.account_id).find_by(id: @brand['import_id'])
    proposal = import&.succeeded? ? import.result : nil
    return [nil, {}] unless proposal.is_a?(Hash)

    from_proposal(proposal, import.url)
  end

  def from_proposal(proposal, url)
    appearance = proposal['appearance'].to_h
    logo = stored_logo(appearance['logo_url'])
    source = proposal.merge('appearance' => appearance.merge('logo_url' => nil))
    snapshot = { 'name' => proposal['name'], 'mode' => @mode, 'source' => 'site', 'source_url' => url }
    [BrandKits::PromptPayload.new(source, mode: @mode, logo_url: logo).to_h, snapshot]
  end

  def from_requested_site
    url = BrandKits::SiteImporter.normalize_url(@requested_url)
    raise BrandKits::SiteImporter::Error, 'rate_limited' if briefing_reads_exhausted?

    proposal = read_site(url)
    import = record_read(url, status: :succeeded, result: proposal.merge(BRIEFING_ORIGIN))
    identity, snapshot = from_proposal(proposal, url)
    [identity.merge(requested_site: host),
     snapshot.merge('site_request' => { 'host' => host, 'status' => 'used', 'import_id' => import.id })]
  rescue StandardError => e
    # Expected: SiteImporter::Error (unsafe, private, timeout...). Anything else still must not stop the e-mail.
    code = e.is_a?(BrandKits::SiteImporter::Error) ? e.code : e.class.name
    Rails.logger.info("[EmailCampaigns::Ai::BrandResolution] campaign=#{@campaign.id} requested site unreadable: #{code}")
    identity, snapshot = chosen
    [identity, snapshot.merge('site_request' => { 'host' => host, 'status' => 'unreadable' })]
  end

  # Every read the request triggers is recorded (failed ones too), so the cap also counts attempts that failed.
  def read_site(url)
    BrandKits::SiteImporter.new(url).perform
  rescue BrandKits::SiteImporter::Error => e
    record_read(url, status: :failed, error_code: e.code, result: BRIEFING_ORIGIN)
    raise
  end

  def record_read(url, **attributes)
    BrandImportJob.create!(account_id: @campaign.account_id, url: url, started_at: Time.current, finished_at: Time.current, **attributes)
  end

  def briefing_reads_exhausted?
    BrandImportJob.where(account_id: @campaign.account_id).from_briefing.last_hour.count >= BrandImportJob::BRIEFING_HOURLY_LIMIT
  end

  def host
    BrandKits::WebAddress.parse(@requested_url)&.host.to_s
  end

  def stored_logo(url)
    return nil if url.blank?

    blob = BrandKits::LogoDownloader.blob_from(url)
    # Direct attachment row: attach would save the campaign while its generation is in flight.
    ActiveStorage::Attachment.create!(record: @campaign, name: 'builder_assets', blob: blob)
    EmailCampaigns::PublicBlobUrl.call(blob)
  rescue BrandKits::LogoDownloader::Error => e
    Rails.logger.info("[EmailCampaigns::Ai::BrandResolution] campaign=#{@campaign.id} logo skipped: #{e.code}")
    nil
  end
end

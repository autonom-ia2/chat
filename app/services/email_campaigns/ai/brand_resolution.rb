# Which visual identity an AI e-mail uses (#1076), resolved in the job from what the composer sent:
#   { 'kit_id' => 1, 'mode' => 'light' }          a kit of the account (archived after the click still counts)
#   { 'import_id' => 9, 'mode' => 'dark' }        a site read for this e-mail only ("Usar outro site")
#   nil / {}                                     no identity: the model picks colors as before
# Returns [identity, snapshot]: the BrandKits::PromptPayload hash for the prompt (or nil) and what the
# campaign records in brand_identity (Resultado shows it). The logo of a site read for one e-mail is
# stored with the campaign (builder_assets) so the e-mail never points at another host for it; when it
# cannot be stored the e-mail goes without logo.
class EmailCampaigns::Ai::BrandResolution
  def initialize(campaign, brand)
    @campaign = campaign
    @brand = brand.is_a?(Hash) ? brand.stringify_keys : {}
    @mode = BrandKits::EmailPalettes::MODES.include?(@brand['mode']) ? @brand['mode'] : BrandKits::EmailPalettes::DEFAULT_MODE
  end

  def call
    return [nil, {}] unless BrandKits::Config.enabled?
    return from_import if @brand['import_id'].present?
    return from_kit if @brand['kit_id'].present?

    [nil, {}]
  end

  private

  def from_kit
    kit = BrandKit.where(account_id: @campaign.account_id).find_by(id: @brand['kit_id'])
    return [nil, {}] if kit.nil?

    [BrandKits::PromptPayload.new(kit, mode: @mode).to_h, { 'kit_id' => kit.id, 'name' => kit.name, 'mode' => @mode, 'source' => 'kit' }]
  end

  def from_import
    import = BrandImportJob.where(account_id: @campaign.account_id).find_by(id: @brand['import_id'])
    proposal = import&.succeeded? ? import.result : nil
    return [nil, {}] unless proposal.is_a?(Hash)

    appearance = proposal['appearance'].to_h
    logo = stored_logo(appearance['logo_url'])
    source = proposal.merge('appearance' => appearance.merge('logo_url' => nil))
    snapshot = { 'name' => proposal['name'], 'mode' => @mode, 'source' => 'site', 'source_url' => import.url }
    [BrandKits::PromptPayload.new(source, mode: @mode, logo_url: logo).to_h, snapshot]
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

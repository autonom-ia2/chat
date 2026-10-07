# One run of the import job (#1099, delivery B), for the worker that holds the import's lock (`token`): reads what came
# in (the pasted model, the .html, the .zip with its images, or the page of the address), converts it with the engine
# (delivery A), copies the images, and stores the MJML and the report — or the code of the failure. The whole run fits
# in JOB_SECONDS: the address, the conversion and the images each get a slice of that deadline, and the lock is renewed
# between the steps. The received input is purged at the end either way; the log carries the error class, never the
# client's markup.
class EmailCampaigns::Import::Run
  JOB_SECONDS = 90
  Input = Data.define(:markup, :base_url, :files)

  def self.call(import, token)
    new(import, token).call
  end

  def initialize(import, token)
    @import = import
    @token = token
    @deadline = EmailCampaigns::Import::Deadline.new(JOB_SECONDS)
  end

  def call
    input = read_input
    result = convert(input)
    mjml = copy_images(result, input)
    raise EmailCampaigns::Import::Error, :too_large if mjml.length > EmailCampaignTemplate::BODY_MAX

    @import.finish!(@token, mjml: mjml, report: result.report.to_h)
  rescue EmailCampaigns::Import::Error => e
    @import.fail!(@token, e.code)
  rescue StandardError => e
    Rails.logger.error("[EmailCampaigns::Import::Run] import #{@import.id} failed: #{e.class}")
    @import.fail!(@token, :internal)
  ensure
    @import.source.purge if @import.source.attached?
  end

  private

  def read_input
    return from_address if @import.source_kind == 'url'
    raise EmailCampaigns::Import::Error, :empty unless @import.source.attached?

    bytes = @import.source.download
    return Input.new(markup: bytes, base_url: nil, files: nil) unless @import.source.content_type == 'application/zip'

    archive = EmailCampaigns::Import::ZipReader.call(bytes)
    Input.new(markup: archive.markup, base_url: archive.base_url, files: archive.files)
  end

  def from_address
    page = EmailCampaigns::Import::UrlSource.call(@import.source_url, deadline: @deadline.slice(EmailCampaigns::Import::UrlSource::TIMEOUT_SECONDS))
    Input.new(markup: page.markup, base_url: page.base_url, files: nil)
  end

  def convert(input)
    @deadline.check!
    budget = EmailCampaigns::Import::Budget.new(seconds: [EmailCampaigns::Import::Limits::TOTAL_SECONDS, @deadline.remaining].min)
    result = EmailCampaigns::Import::Engine.call(input.markup, source_kind: @import.source_kind, base_url: input.base_url, budget: budget)
    @deadline.check!
    @import.extend_lock!(@token)
    result
  end

  def copy_images(result, input)
    mjml = EmailCampaigns::Import::ImageRehoster.call(result.mjml, result.report, import: @import, files: input.files || {},
                                                                                  deadline: @deadline)
    mjml = EmailCampaigns::Import::ArchiveLinks.call(mjml, result.report) if input.files
    @deadline.check!
    mjml
  end
end

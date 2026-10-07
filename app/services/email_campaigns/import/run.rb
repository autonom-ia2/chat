# One run of the import job (#1099, delivery B), for the worker that holds the import's lock (`token`): reads what came
# in (the pasted model, the .html, the .zip with its images, or the page of the address, in the charset it answered
# with), converts it with the engine (delivery A), copies the images, and stores the MJML, the report and what blocks
# the saving (SaveCheck, so following the import does not recompute it) — or the code of the failure. The whole run fits
# in JOB_SECONDS: the address, the conversion and the images each get a slice of that deadline, and the lock is renewed
# between the steps. The received input is purged only when this worker's guarded write landed: one that lost the
# import to a newer attempt leaves the input to that attempt. An unexpected error goes to the error tracker as its class
# and backtrace only — never its message, which may carry the client's markup.
class EmailCampaigns::Import::Run
  JOB_SECONDS = 90
  Input = Data.define(:markup, :base_url, :files, :charset) do
    def initialize(markup:, base_url: nil, files: nil, charset: nil)
      super
    end
  end
  Crash = Class.new(StandardError)

  def self.call(import, token)
    new(import, token).call
  end

  def initialize(import, token)
    @import = import
    @token = token
    @deadline = EmailCampaigns::Import::Deadline.new(JOB_SECONDS)
  end

  def call
    @settled = settle
  ensure
    @import.source.purge if @settled && @import.source.attached?
  end

  private

  def settle
    input = read_input
    result = convert(input)
    mjml = copy_images(result, input)
    raise EmailCampaigns::Import::Error, :too_large if mjml.length > EmailCampaignTemplate::BODY_MAX

    @import.finish!(@token, mjml: mjml, report: result.report.to_h, blocking: EmailCampaigns::Import::SaveCheck.call(mjml, @import))
  rescue EmailCampaigns::Import::Error => e
    @import.fail!(@token, e.code)
  rescue StandardError => e
    track(e)
    @import.fail!(@token, :internal)
  end

  def track(error)
    crash = Crash.new(error.class.name)
    crash.set_backtrace(error.backtrace)
    ChatwootExceptionTracker.new(crash, account: @import.account).capture_exception
  end

  def read_input
    return from_address if @import.source_kind == 'url'
    raise EmailCampaigns::Import::Error, :empty unless @import.source.attached?

    bytes = @import.source.download
    return Input.new(markup: bytes) unless @import.source.content_type == 'application/zip'

    archive = EmailCampaigns::Import::ZipReader.call(bytes)
    Input.new(markup: archive.markup, base_url: archive.base_url, files: archive.files)
  end

  def from_address
    page = EmailCampaigns::Import::UrlSource.call(@import.source_url, deadline: @deadline.slice(EmailCampaigns::Import::UrlSource::TIMEOUT_SECONDS))
    Input.new(markup: page.markup, base_url: page.base_url, charset: page.charset)
  end

  def convert(input)
    @deadline.check!
    budget = EmailCampaigns::Import::Budget.new(seconds: [EmailCampaigns::Import::Limits::TOTAL_SECONDS, @deadline.remaining].min)
    result = EmailCampaigns::Import::Engine.call(input.markup, source_kind: @import.source_kind, base_url: input.base_url, budget: budget,
                                                               charset: input.charset)
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

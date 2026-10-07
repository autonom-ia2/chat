# "Refazer para editar" (#1099, delivery D): the AI rebuilds ONE part the converter left as an image — and only that
# part — with our editable blocks. Started by a click (Starter, which counts the part against MAX_PER_IMPORT and the
# account's monthly Quota), it runs in RebuildJob for the click that holds the part's `token`:
#   1. the part's cleaned markup (kept by the report) goes to the e-mail model as inert data under a fixed instruction
#      (PromptBuilder.convert_fragment), never as instructions (Fragment);
#   2. the answer goes through the importer's own MJML path — allowlist, cleaning, merge tags — and must be made only of
#      editable blocks, with exactly the visible words of the original part and no link or image the part did not have
#      (Answer);
#   3. its images are copied like the import's, then it takes the placeholder's place (Splice), and the design goes
#      through the canonicalizer, our locked footer, the quality fixes and the check before saving (SaveCheck).
# Any step that fails leaves the design as it was — the part stays an image, with its warning — and marks the part
# "não deu" with a reason code. State per part lives in the import's `rebuilds`: running, done or failed; a running one
# older than SECONDS is a job that died, shown (and settled) as failed. Nothing of the client's markup is logged.
class EmailCampaigns::Import::PartRebuild
  MAX_PER_IMPORT = 5
  SECONDS = 180
  REQUEST_SECONDS = 120
  REASONING = 'medium'.freeze
  FEATURE = 'email'.freeze
  RUNNING = 'running'.freeze
  DONE = 'done'.freeze
  FAILED = 'failed'.freeze
  SCHEMA = {
    name: 'email_import_convert_fragment',
    schema: {
      type: 'object', properties: { mjml: { type: 'string' } },
      required: ['mjml'], additionalProperties: false
    }
  }.freeze

  # Why a part could not be rebuilt; the reason is kept on the part (never the client's markup).
  class Failure < StandardError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("part not rebuilt: #{reason}")
    end
  end

  def self.available?(account)
    Crm::Ai::CredentialResolver.new(account: account).configured?
  end

  # The state of every part the person asked to rebuild, for the screen: { id => { status:, reason: } }.
  def self.view(import, now = Time.current)
    import.rebuilds.to_h.transform_values do |entry|
      stale = entry['status'] == RUNNING && started_at(entry) < now - SECONDS
      { status: stale ? FAILED : entry['status'], reason: stale ? 'timeout' : entry['reason'] }.compact
    end
  end

  def self.started_at(entry)
    Time.zone.parse(entry['started_at'].to_s) || Time.zone.at(0)
  end

  def self.call(import, target, token, client: nil)
    new(import, target, token, client).call
  end

  def initialize(import, target, token, client)
    @import = import
    @target = target
    @token = token
    @client = client
  end

  def call
    return unless current?(@import.rebuilds[@target])

    fragment = EmailCampaigns::Import::PartRebuild::Fragment.for(@import, @target)
    raise Failure, :gone if fragment.nil?

    document = EmailCampaigns::Import::PartRebuild::Answer.call(ask(fragment), fragment)
    apply(copy_images(document))
  rescue Failure => e
    settle(FAILED, e.reason)
  rescue StandardError => e
    track(e)
    settle(FAILED, :internal)
  end

  private

  def current?(entry)
    entry.present? && entry['status'] == RUNNING && entry['token'] == @token && self.class.started_at(entry) >= SECONDS.seconds.ago
  end

  def ask(fragment)
    response = client.create(model: Crm::Ai::Config::MODEL_EMAIL, instructions: EmailCampaigns::Ai::PromptBuilder.convert_fragment,
                             input: fragment.input, schema: SCHEMA, reasoning_effort: REASONING, timeout: REQUEST_SECONDS)
    response[:text]
  rescue Crm::Ai::ResponsesClient::Error
    raise Failure, :provider
  end

  def client
    return @client if @client

    credential = Crm::Ai::CredentialResolver.new(account: @import.account).resolve
    unless credential
      EmailCampaigns::Import::PartRebuild::Quota.give_back(@import.account, @import.rebuilds.dig(@target, 'period'))
      raise Failure, :ai_not_configured
    end

    Crm::Ai::ResponsesClient.new(credential: credential, feature: FEATURE, account: @import.account, max_retries: 1)
  end

  # The images of the rebuilt part are copied like the import's; one that does not come becomes the "image to swap"
  # placeholder (a section background: the missing-background mark), which the person solves like any other.
  def copy_images(document)
    report = EmailCampaigns::Import::Report.new(source_kind: @import.source_kind)
    report.images = EmailCampaigns::Import::ImageList.from(document)
    return document if report.images.empty?

    copies = EmailCampaigns::Import::ImageRehoster.rehost(EmailCampaigns::Import::Emitter.call(document), report, import: @import).copies
    EmailCampaigns::Import::PartRebuild::Images.point(document, copies)
  end

  def apply(document)
    @import.with_lock do
      raise Failure, :gone unless @import.status == 'ready'
      next unless current?(@import.rebuilds[@target])

      mjml = finished(EmailCampaigns::Import::PartRebuild::Splice.call(@import.result_mjml.to_s, @target, document))
      blocking = checked(mjml)
      @import.update!(result_mjml: mjml, blocking: blocking, fixes: @import.fixes + [fix_record],
                      rebuilds: rebuilds_with(DONE, nil))
    end
  end

  def finished(mjml)
    footed = EmailCampaigns::LockedFooter.ensure(mjml)
    scratch = EmailCampaigns::Import::Report.new(source_kind: @import.source_kind)
    fixed = EmailCampaigns::Import::QualityFix.call(footed, scratch, placeholders: EmailCampaigns::Import::Engine::PLACEHOLDERS)
    raise Failure, :too_large if fixed.length > EmailCampaignTemplate::BODY_MAX

    fixed
  end

  # The rebuilt design must still keep every rule the importer guarantees, and the part must be gone for good.
  def checked(mjml)
    blocking = EmailCampaigns::Import::SaveCheck.call(mjml, @import)
    raise Failure, :invalid if blocking.any? { |entry| entry[:code] == :invalid }
    raise Failure, :not_replaced if blocking.any? { |entry| entry[:code] == :unresolved_parts && entry[:items].include?(@target) }

    blocking
  end

  def fix_record
    { 'code' => 'unresolved_parts', 'choice' => 'rebuild', 'target' => @target, 'at' => Time.current.iso8601 }
  end

  def rebuilds_with(status, reason)
    entry = @import.rebuilds[@target].merge('status' => status, 'reason' => reason&.to_s, 'finished_at' => Time.current.iso8601)
    @import.rebuilds.merge(@target => entry.compact)
  end

  def settle(status, reason)
    @import.with_lock do
      next unless current?(@import.rebuilds[@target])

      @import.update!(rebuilds: rebuilds_with(status, reason))
    end
  end

  def track(error)
    crash = EmailCampaigns::Import::Run::Crash.new(error.class.name)
    crash.set_backtrace(error.backtrace)
    ChatwootExceptionTracker.new(crash, account: @import.account).capture_exception
  end
end

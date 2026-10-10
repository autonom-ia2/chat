# Starts an import (#1099, delivery B): checks what came in before anything is stored — the pasted model (at most
# 500 KB), the file (an .html of at most 500 KB or a .zip of at most 2 MB, told apart by their bytes with Marcel) or the
# address (https only) — frees the account from an import whose job died (expired lock), creates the record, keeps the
# input as an attachment for the job and queues it. A second import while one is active fails with :in_progress (the
# partial unique index decides, even under concurrent requests).
class EmailCampaigns::Import::Starter
  RATE_LIMIT = 10
  RATE_WINDOW = 10.minutes
  HTML_TYPES = %w[text/html application/xhtml+xml text/plain].freeze
  ZIP_TYPES = %w[application/zip application/x-zip-compressed].freeze
  PAGE_FILENAME = 'modelo.html'.freeze

  def self.rate_limited?(account)
    EmailCampaignTemplateImport.where(account: account, created_at: RATE_WINDOW.ago..).count >= RATE_LIMIT
  end

  def self.call(account:, user:, params:)
    new(account, user, params).call
  end

  def initialize(account, user, params)
    @account = account
    @user = user
    @params = params
  end

  def call
    kind = @params[:source_kind].to_s
    raise EmailCampaigns::Import::Error, :invalid_source_kind unless EmailCampaignTemplateImport::SOURCE_KINDS.include?(kind)

    attachment = input_for(kind)
    import = create(kind, attachment)
    EmailCampaigns::Import::RunJob.perform_later(import.id)
    import
  end

  private

  def input_for(kind)
    case kind
    when 'paste' then pasted
    when 'file' then uploaded
    when 'url' then (@url = EmailCampaigns::Import::UrlSource.check!(@params[:url])) && nil
    end
  end

  def create(kind, attachment)
    EmailCampaignTemplateImport.transaction do
      EmailCampaignTemplateImport.active.where(account: @account).find_each { |stale| stale.stall! if stale.lock_expired? }
      import = EmailCampaignTemplateImport.new(account: @account, user: @user, source_kind: kind, source_url: @url)
      import.source.attach(attachment) if attachment
      import.save!
      import
    end
  rescue ActiveRecord::RecordNotUnique
    raise EmailCampaigns::Import::Error, :in_progress
  end

  def pasted
    content = @params[:content].to_s
    raise EmailCampaigns::Import::Error, :too_large if content.bytesize > EmailCampaigns::Import::Limits::MAX_BYTES
    raise EmailCampaigns::Import::Error, :empty if content.strip.empty?

    { io: StringIO.new(content), filename: PAGE_FILENAME, content_type: 'text/html' }
  end

  def uploaded
    file = @params[:file]
    raise EmailCampaigns::Import::Error, :empty unless file.respond_to?(:tempfile) && file.size.to_i.positive?

    zip = ZIP_TYPES.include?(detected_type(file))
    limit, code = zip ? [EmailCampaigns::Import::ZipReader::MAX_BYTES, :zip_too_large] : [EmailCampaigns::Import::Limits::MAX_BYTES, :too_large]
    raise EmailCampaigns::Import::Error, code if file.size > limit

    { io: StringIO.new(File.binread(file.tempfile.path)), filename: zip ? 'modelo.zip' : PAGE_FILENAME,
      content_type: zip ? 'application/zip' : 'text/html' }
  end

  def detected_type(file)
    file.tempfile.rewind
    type = Marcel::MimeType.for(file.tempfile, name: file.original_filename.to_s).to_s
    return type if ZIP_TYPES.include?(type) || HTML_TYPES.include?(type)

    raise EmailCampaigns::Import::Error, :unsupported_file
  ensure
    file.tempfile.rewind
  end
end

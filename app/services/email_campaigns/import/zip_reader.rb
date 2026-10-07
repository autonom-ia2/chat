# Reads an uploaded .zip of an e-mail model (#1099, delivery B) in memory, entry by entry, without ever writing it to
# disk: at most 2 MB compressed, 30 files and 10 MB once uncompressed — counted on the bytes actually read, not on what
# the archive announces, so a zip bomb stops at the ceiling. Symbolic links, absolute paths and ".." are refused. The
# page is the shallowest index.html (else the shallowest .html); its images are found by their relative name through a
# base address on a reserved domain (.invalid never resolves), which the image step reads from the archive instead of
# the network. Path and name handling with String and URI methods — no regex.
class EmailCampaigns::Import::ZipReader
  BASE_URL = 'https://arquivo-importado.invalid/'.freeze
  MAX_BYTES = 2 * 1024 * 1024
  MAX_UNCOMPRESSED = 10 * 1024 * 1024
  MAX_FILES = 30
  MAX_ENTRIES = 200
  CHUNK = 64 * 1024
  PAGE_EXTENSIONS = %w[.html .htm].freeze
  SKIPPED_FOLDERS = %w[__MACOSX].freeze

  Result = Data.define(:markup, :base_url, :files)

  def self.call(bytes)
    new(bytes).call
  end

  # The bytes of an image of the archive, by the absolute address the engine gave it (nil when it is not one).
  def self.file_for(files, src)
    return unless src.to_s.start_with?(BASE_URL)

    path = URI.decode_uri_component(URI.parse(src).path.to_s.delete_prefix('/'))
    files[path]
  rescue URI::InvalidURIError, ArgumentError
    nil
  end

  def initialize(bytes)
    @bytes = bytes.to_s.b
  end

  def call
    raise EmailCampaigns::Import::Error, :zip_too_large if @bytes.bytesize > MAX_BYTES

    files = read_entries
    page = choose_page(files.keys)
    raise EmailCampaigns::Import::Error, :zip_no_html if page.nil?

    Result.new(markup: files.delete(page).force_encoding(Encoding::UTF_8), base_url: base_for(page), files: files)
  end

  private

  def read_entries
    files = {}
    @total = 0
    Zip::File.open_buffer(StringIO.new(@bytes)) do |zip|
      kept_entries(zip).each do |entry|
        name = safe_name(entry)
        files[name] = read(entry) if entry.file?
      end
    end
    files
  rescue Zip::EntryNameError
    raise EmailCampaigns::Import::Error, :zip_unsafe_path
  rescue Zip::Error, Zlib::Error, IOError
    raise EmailCampaigns::Import::Error, :zip_invalid
  end

  def kept_entries(zip)
    entries = zip.entries
    raise EmailCampaigns::Import::Error, :zip_too_many_files if entries.size > MAX_ENTRIES

    kept = entries.reject { |entry| skipped?(entry) }
    raise EmailCampaigns::Import::Error, :zip_too_many_files if kept.count(&:file?) > MAX_FILES

    kept
  end

  def skipped?(entry)
    segments = name_of(entry).split('/')
    SKIPPED_FOLDERS.include?(segments.first) || segments.last.to_s.start_with?('.')
  end

  def safe_name(entry)
    name = name_of(entry)
    raise EmailCampaigns::Import::Error, :zip_unsafe_path if unsafe?(entry, name)

    name
  end

  def unsafe?(entry, name)
    entry.symlink? || name.start_with?('/') || name.include?('\\') || name.split('/').first.to_s.include?(':') ||
      name.split('/').include?('..')
  end

  def name_of(entry)
    entry.name.to_s.dup.force_encoding(Encoding::UTF_8).scrub('')
  end

  def read(entry)
    out = +''.b
    stream = entry.get_input_stream
    while (chunk = stream.read(CHUNK))
      @total += chunk.bytesize
      raise EmailCampaigns::Import::Error, :zip_too_large if @total > MAX_UNCOMPRESSED

      out << chunk
    end
    out
  ensure
    stream&.close
  end

  def choose_page(names)
    pages = names.select { |name| PAGE_EXTENSIONS.include?(File.extname(name).downcase) }
    pages.min_by { |name| [File.basename(name).downcase == 'index.html' ? 0 : 1, name.count('/'), name] }
  end

  def base_for(page)
    folder = File.dirname(page)
    return BASE_URL if folder == '.'

    "#{BASE_URL}#{folder.split('/').map { |segment| URI.encode_uri_component(segment) }.join('/')}/"
  end
end

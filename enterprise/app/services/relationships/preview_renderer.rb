require 'timeout'

# Local converters receive bounded regular files, never shell commands or URLs.
class Relationships::PreviewRenderer
  MAX_INPUT = 25 * 1024 * 1024
  MAX_OUTPUT = 2 * 1024 * 1024
  MAX_MEMORY = 512 * 1024 * 1024
  TIMEOUT = 15
  IMAGE_TYPES = %w[image/jpeg image/png image/webp].freeze
  IMAGE_FORMATS = { 'image/jpeg' => 'jpeg_pipe', 'image/png' => 'png_pipe', 'image/webp' => 'webp_pipe' }.freeze
  VIDEO_FORMATS = { 'video/mp4' => 'mov', 'video/quicktime' => 'mov', 'video/webm' => 'matroska', 'video/x-matroska' => 'matroska' }.freeze

  def self.supported?(content_type)
    IMAGE_TYPES.include?(content_type) || content_type == 'application/pdf' || VIDEO_FORMATS.key?(content_type)
  end

  def render(content_type, input, output)
    return false unless File.file?(input) && File.size(input).between?(1, MAX_INPUT)

    command = command_for(content_type, input, output)
    return false unless command && run_bounded(command)

    valid_output?(output)
  rescue Timeout::Error
    false
  end

  private

  def valid_output?(output)
    File.file?(output) && File.size(output).between?(1, MAX_OUTPUT) && File.binread(output, 2) == "\xFF\xD8".b
  end

  def command_for(content_type, input, output)
    return if IMAGE_TYPES.include?(content_type) && !image_signature?(content_type, input)

    if content_type == 'application/pdf'
      return unless File.binread(input, 5) == '%PDF-'

      return ['pdftoppm', '-f', '1', '-singlefile', '-scale-to', '320', '-jpeg', input, output.delete_suffix('.jpg')]
    end

    format = IMAGE_FORMATS[content_type] || VIDEO_FORMATS[content_type]
    return unless format

    ffmpeg_command(format, input, output)
  end

  def ffmpeg_command(format, input, output)
    # Force the demuxer: an uploaded playlist cannot activate HLS/concat or nested inputs.
    # Explicitly disable MOV external data references, including absolute file paths.
    input_options = format == 'mov' ? %w[-enable_drefs 0 -use_absolute_path 0] : []
    # The same native converter handles images and video under the unchanged 512 MiB limit.
    # A Ruby/vips bootstrap must not consume the image worker's bounded address space.
    ['ffmpeg', '-nostdin', '-v', 'error', '-protocol_whitelist', 'file', '-format_whitelist', format,
     '-f', format, *input_options, '-threads', '1', '-filter_threads', '1', '-filter_complex_threads', '1', '-i', input,
     '-map', '0:v:0', '-frames:v', '1', '-vf', "scale=w='min(320,iw)':h='min(240,ih)':force_original_aspect_ratio=decrease",
     '-threads', '1', output]
  end

  def image_signature?(content_type, input)
    header = File.binread(input, 12)
    case content_type
    when 'image/png' then header.start_with?("\x89PNG\r\n\x1A\n".b)
    when 'image/jpeg' then header.start_with?("\xFF\xD8\xFF".b)
    when 'image/webp' then header.start_with?('RIFF') && header.byteslice(8, 4) == 'WEBP'
    end
  end

  def run_bounded(command)
    limits = { rlimit_cpu: 10, rlimit_fsize: MAX_OUTPUT, rlimit_nofile: 64 }
    # Production is Linux. macOS rejects both RLIMIT_AS and RLIMIT_RSS (EINVAL);
    # native converter tests there do not certify the production memory limit.
    limits[:rlimit_as] = MAX_MEMORY unless RUBY_PLATFORM.include?('darwin')
    pid = Process.spawn({ 'VIPS_CONCURRENCY' => '1', 'VIPS_BLOCK_UNTRUSTED' => '1', 'OMP_NUM_THREADS' => '1' }, *command,
                        out: File::NULL, err: File::NULL, pgroup: true, **limits)
    Timeout.timeout(TIMEOUT) { Process.wait2(pid).last.success? }
  rescue Timeout::Error
    Process.kill('KILL', -pid)
    Process.wait(pid)
    raise
  end
end

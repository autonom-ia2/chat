require 'open3'

# Vídeo do topo de um modelo que o WhatsApp entrega (#2370). O WhatsApp só entrega MP4 com vídeo H.264 e áudio AAC, até
# 16 MB (documentação "Media" da Meta, lida em 29/10/2026). A Meta aceita outro formato na criação do modelo e na subida
# para o envio, mas não entrega: cada pessoa fica com 131053. A gravação do iPhone sai em HEVC (H.265), muitas vezes .mov.
# Aqui a pessoa sobe `.mp4` ou `.mov` como tiver: o que já serve passa sem mexer (`ready`); o resto é convertido com o
# ffmpeg do servidor (a imagem de produção e a CI já o trazem) para MP4 H.264/AAC que caiba em 16 MB (`open_converted`).
# A conversão leva dezenas de segundos em 2 vCPU: roda num job (`VideoConversion`), nunca no pedido web.
module Whatsapp::Templates::VideoForMeta
  INPUT_TYPES = %w[video/mp4 video/quicktime].freeze
  # O arquivo que a pessoa escolhe; o de 16 MB vale para o que vai à Meta.
  INPUT_MAX = 100.megabytes
  OUTPUT_TYPE = 'video/mp4'.freeze
  # 16 MB decimais: o menor dos dois jeitos de contar.
  OUTPUT_MAX = 16_000_000
  # Folga para o cabeçalho do MP4 e a variação do codificador.
  SIZE_MARGIN = 0.9
  AUDIO_KBPS = 96
  MAX_VIDEO_KBPS = 2500
  # Abaixo disso o vídeo fica ilegível: o vídeo é longo demais para 16 MB.
  MIN_VIDEO_KBPS = 250
  MAX_SIDE = 1280
  PROBE_TIMEOUT = 20
  CONVERT_TIMEOUT = 300
  # O worker divide a máquina com o painel: o ffmpeg usa 2 núcleos e cede a vez.
  CONVERT_PREFIX = %w[nice -n 10].freeze

  # Recusa da subida como as do `Manager`: `code` vira o texto da tela (whatsapp_templates.errors.*).
  class Invalid < Whatsapp::Templates::Manager::Refused; end

  Media = Data.define(:io, :file_name, :content_type) do
    def size = io.size
  end

  module_function

  # O arquivo como está, quando não é vídeo ou o vídeo já serve; nil quando precisa converter. Vídeo grande demais ou
  # que o ffprobe não lê é recusado aqui, ainda no pedido.
  def ready(file, content_type)
    media = Media.new(io: file, file_name: file.original_filename.to_s, content_type: content_type)
    return media unless INPUT_TYPES.include?(content_type)
    raise Invalid, 'video_too_large' if file.size > INPUT_MAX

    media.with(content_type: OUTPUT_TYPE) if deliverable?(probe(file.path), content_type, file.size)
  end

  # Entrega ao bloco o vídeo convertido e, no fim, apaga o arquivo temporário.
  def open_converted(path, name)
    out = convert(path, probe(path))
    yield Media.new(io: out, file_name: mp4_name(name), content_type: OUTPUT_TYPE)
  ensure
    out&.close!
  end

  # { video:, pix_fmt:, audio:, duration: segundos }
  def probe(path)
    out = run(PROBE_TIMEOUT, 'ffprobe', '-v', 'error', '-protocol_whitelist', 'file', '-show_entries',
              'stream=codec_type,codec_name,pix_fmt,duration:format=duration', '-of', 'json', path)
    data = JSON.parse(out)
    video = Array(data['streams']).find { |stream| stream['codec_type'] == 'video' }
    raise Invalid, 'video_unreadable' if video.blank?

    audio = Array(data['streams']).find { |stream| stream['codec_type'] == 'audio' }
    { video: video['codec_name'], pix_fmt: video['pix_fmt'], audio: audio&.dig('codec_name'),
      duration: (data.dig('format', 'duration') || video['duration']).to_f }
  rescue JSON::ParserError
    raise Invalid, 'video_unreadable'
  end

  # 4:2:0 de 8 bits é o que todo celular toca; H.264 de 10 bits ou 4:2:2 também é convertido.
  def deliverable?(info, content_type, size)
    content_type == OUTPUT_TYPE && info[:video] == 'h264' && info[:pix_fmt] == 'yuv420p' &&
      [nil, 'aac'].include?(info[:audio]) && size <= OUTPUT_MAX
  end

  # O bitrate sai da duração, para o resultado caber em 16 MB.
  def convert(path, info)
    video_kbps = video_kbps(info[:duration])
    out = Tempfile.new(['video_for_meta', '.mp4'], binmode: true)
    run(CONVERT_TIMEOUT, *CONVERT_PREFIX, 'ffmpeg', '-nostdin', '-y', '-v', 'error', '-protocol_whitelist', 'file',
        '-i', path, '-map', '0:v:0', '-map', '0:a:0?', '-threads', '2',
        '-vf', "scale=w='min(#{MAX_SIDE},iw)':h='min(#{MAX_SIDE},ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
        '-c:v', 'libx264', '-preset', 'veryfast', '-profile:v', 'main', '-pix_fmt', 'yuv420p',
        '-b:v', "#{video_kbps}k", '-maxrate', "#{video_kbps}k", '-bufsize', "#{video_kbps * 2}k",
        '-c:a', 'aac', '-b:a', "#{AUDIO_KBPS}k", '-ac', '2', '-movflags', '+faststart', out.path)
    out.rewind
    raise Invalid, 'video_too_long' if out.size > OUTPUT_MAX

    out
  rescue Exception # rubocop:disable Lint/RescueException
    # Qualquer interrupção (inclusive o fim do worker) apaga o temporário.
    out&.close!
    raise
  end

  def video_kbps(duration)
    raise Invalid, 'video_unreadable' unless duration.positive?

    budget = ((OUTPUT_MAX * SIZE_MARGIN * 8) / duration / 1000).floor - AUDIO_KBPS
    raise Invalid, 'video_too_long' if budget < MIN_VIDEO_KBPS

    [budget, MAX_VIDEO_KBPS].min
  end

  def mp4_name(name)
    "#{File.basename(name.to_s, '.*').presence || 'video'}.mp4"
  end

  # Sem shell: cada argumento vai como está. Passou do tempo, ou o pedido foi interrompido, o processo é morto.
  def run(timeout, *command)
    Open3.popen3(*command) do |stdin, stdout, stderr, wait|
      stdin.close
      output = Thread.new { stdout.read }
      errors = Thread.new { stderr.read }
      begin
        raise Invalid, 'video_unreadable' unless wait.join(timeout)
      ensure
        kill(wait)
      end
      unless wait.value.success?
        Rails.logger.warn("[whatsapp_templates][video_for_meta] #{command.first} falhou: #{errors.value.to_s.first(300)}")
        raise Invalid, 'video_unreadable'
      end

      output.value
    end
  rescue Errno::ENOENT
    Rails.logger.error("[whatsapp_templates][video_for_meta] #{command.first} ausente")
    raise Invalid, 'video_unreadable'
  end

  def kill(wait)
    Process.kill('KILL', wait.pid) if wait.alive?
  rescue Errno::ESRCH
    nil
  end
end

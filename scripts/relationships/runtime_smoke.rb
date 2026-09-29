# Run only in the disposable, network-disabled image built by the Relationships CI.
require 'bundler/setup'
require 'json'
require 'digest'
require 'tmpdir'
require 'fileutils'
require 'rbconfig'
require 'active_support/all'
require 'vips'
module Relationships; end
require '/app/enterprise/app/services/relationships/preview_renderer'

abort 'Linux Ruby 3.4.4 runtime required' unless RUBY_PLATFORM.include?('linux') && RUBY_VERSION == '3.4.4'
expected = ENV.fetch('EXPECTED_COMMIT')
abort 'Image commit mismatch' unless File.read('/app/.git_sha').strip == expected
renderer = Relationships::PreviewRenderer.new
results = []
check = lambda do |name, &assertion|
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  warn "RUNTIME_CHECK #{name}"
  assertion.call
  results << { name: name, passed: true, seconds: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start).round(3) }
end
ensure_true = lambda do |condition, message|
  raise message unless condition
end

directory = Dir.mktmpdir('relationships-runtime-')
begin
  { 'png' => 'image/png', 'pdf' => 'application/pdf', 'mp4' => 'video/mp4' }.each do |extension, type|
    check.call("real #{extension} preview") do
      input = "/qa-assets/sample.#{extension}"
      original_digest = Digest::SHA256.file(input).hexdigest
      output = File.join(directory, "#{extension}.jpg")
      rendered = renderer.render(type, input, output)
      unless rendered
        command = renderer.send(:command_for, type, input, output)
        warn "CONVERTER_DIAGNOSTIC #{type}"
        # Synthetic CI fixtures only. Preserve the same resource limits while surfacing stderr.
        limits = { rlimit_cpu: 10, rlimit_fsize: Relationships::PreviewRenderer::MAX_OUTPUT,
                   rlimit_nofile: 64, rlimit_as: Relationships::PreviewRenderer::MAX_MEMORY }
        pid = Process.spawn({ 'VIPS_CONCURRENCY' => '1', 'VIPS_BLOCK_UNTRUSTED' => '1', 'OMP_NUM_THREADS' => '1' },
                            *command, out: File::NULL, err: $stderr, **limits)
        Timeout.timeout(Relationships::PreviewRenderer::TIMEOUT) { Process.wait(pid) }
      end
      ensure_true.call(rendered, "#{type} did not render")
      image = Vips::Image.jpegload(output)
      ensure_true.call(image.width <= 320 && image.height <= 320, 'preview dimensions exceeded')
      ensure_true.call(File.size(output) <= Relationships::PreviewRenderer::MAX_OUTPUT, 'preview size exceeded')
      ensure_true.call(Digest::SHA256.file(input).hexdigest == original_digest, 'original changed')
    end
  end
  { 'jpg' => 'image/jpeg', 'webp' => 'image/webp' }.each do |extension, type|
    check.call("explicit #{extension} loader") do
      input = File.join(directory, "source.#{extension}")
      Vips::Image.pngload('/qa-assets/sample.png').write_to_file(input)
      ensure_true.call(renderer.render(type, input, File.join(directory, "from-#{extension}.jpg")), 'image loader failed')
    end
  end
  check.call('mismatched active image and nested playlist are rejected') do
    bad_image = File.join(directory, 'disguised.png')
    File.write(bad_image, '<svg xmlns="http://www.w3.org/2000/svg"><image href="file:///etc/passwd"/><image href="http://127.0.0.1:9/unreachable"/></svg>')
    Relationships::PreviewRenderer::IMAGE_TYPES.each do |type|
      ensure_true.call(!renderer.render(type, bad_image, File.join(directory, 'disguised.jpg')), 'active image accepted')
    end
    playlist = File.join(directory, 'playlist.mp4')
    File.write(playlist, "ffconcat version 1.0\nfile '/qa-assets/sample.mp4'\n")
    ensure_true.call(!renderer.render('video/mp4', playlist, File.join(directory, 'playlist.jpg')), 'nested playlist accepted')
  end
  check.call('corrupt file and unsupported audio have safe fallback') do
    broken = File.join(directory, 'broken.pdf')
    File.write(broken, '%PDF-corrupt-synthetic')
    ensure_true.call(!renderer.render('application/pdf', broken, File.join(directory, 'broken.jpg')), 'corrupt PDF accepted')
    ensure_true.call(!renderer.render('audio/mpeg', broken, File.join(directory, 'audio.jpg')), 'audio converted')
  end
  check.call('maximum input size is enforced') do
    oversized = File.join(directory, 'oversized.pdf')
    File.open(oversized, 'wb') { |file| file.truncate(Relationships::PreviewRenderer::MAX_INPUT + 1) }
    ensure_true.call(!renderer.render('application/pdf', oversized, File.join(directory, 'oversized.jpg')), 'oversized input accepted')
  end
  check.call('Linux child address-space limit prevents excessive allocation') do
    command = [RbConfig.ruby, '-e', 'data = "x" * (1024 * 1024 * 1024); puts data.bytesize']
    ensure_true.call(!renderer.send(:run_bounded, command), 'unbounded memory child succeeded')
  end
  check.call('Linux output file limit is enforced') do
    output = File.join(directory, 'oversize-output')
    command = [RbConfig.ruby, '-e', 'File.binwrite(ARGV[0], "x" * (3 * 1024 * 1024))', output]
    ensure_true.call(!renderer.send(:run_bounded, command), 'unbounded output child succeeded')
    ensure_true.call(!File.exist?(output) || File.size(output) <= Relationships::PreviewRenderer::MAX_OUTPUT, 'file size limit exceeded')
  end
  check.call('wall timeout terminates the converter process group') do
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    timed_out = false
    begin
      renderer.send(:run_bounded, [RbConfig.ruby, '-e', 'sleep 40'])
    rescue Timeout::Error
      timed_out = true
    end
    ensure_true.call(timed_out, 'wall-time timeout did not trigger')
    ensure_true.call(Process.clock_gettime(Process::CLOCK_MONOTONIC) - start < Relationships::PreviewRenderer::TIMEOUT + 5, 'timeout was not bounded')
  end
ensure
  FileUtils.remove_entry(directory)
end
puts JSON.pretty_generate({ commit: expected, ruby: RUBY_VERSION, platform: RUBY_PLATFORM, checks: results })

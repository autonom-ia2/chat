require 'rails_helper'

# Entrada .zip (#1099, entrega B): lida em memória, por stream, com tetos de tamanho compactado, descompactado e de
# arquivos; nada de link simbólico, caminho absoluto ou "..".
RSpec.describe EmailCampaigns::Import::ZipReader, :aggregate_failures do
  def zip(entries)
    Zip::OutputStream.write_buffer do |stream|
      entries.each do |name, content|
        stream.put_next_entry(name)
        stream.write(content)
      end
    end.string
  end

  def code_of(bytes)
    described_class.call(bytes)
    nil
  rescue EmailCampaigns::Import::Error => e
    e.code
  end

  let(:html) { '<html><body><img src="img/logo.png" alt="Logo"><p>Oi</p></body></html>' }

  it 'returns the page, the images by their relative name and a base that keeps them apart from the internet' do
    result = described_class.call(zip('modelo/index.html' => html, 'modelo/img/logo.png' => 'PNGDATA', '__MACOSX/._x' => 'x'))

    expect(result.markup).to include('Oi')
    expect(result.base_url).to eq("#{described_class::BASE_URL}modelo/")
    expect(result.files).to eq('modelo/img/logo.png' => 'PNGDATA')
    expect(described_class.file_for(result.files, "#{described_class::BASE_URL}modelo/img/logo.png")).to eq('PNGDATA')
  end

  it 'prefers index.html at the shallowest level when there are several pages' do
    result = described_class.call(zip('a/b/outra.html' => '<p>Outra</p>', 'index.html' => '<p>Principal</p>'))

    expect(result.markup).to include('Principal')
    expect(result.base_url).to eq(described_class::BASE_URL)
  end

  it 'reads names with spaces through their percent-encoded address' do
    result = described_class.call(zip('index.html' => html, 'minha foto.jpg' => 'JPG'))

    expect(described_class.file_for(result.files, "#{described_class::BASE_URL}minha%20foto.jpg")).to eq('JPG')
    expect(described_class.file_for(result.files, 'https://example.com/minha%20foto.jpg')).to be_nil
  end

  it 'refuses a zip bomb: more than 10 MB once uncompressed' do
    bomb = zip('index.html' => html, 'zeros.png' => "\0" * (10.megabytes + 1))

    expect(bomb.bytesize).to be < 100.kilobytes
    expect(code_of(bomb)).to eq(:zip_too_large)
  end

  it 'refuses more than 2 MB compressed' do
    expect(code_of("PK#{SecureRandom.random_bytes(2.megabytes)}")).to eq(:zip_too_large)
  end

  it 'refuses more than 30 files' do
    entries = (1..31).to_h { |index| ["img#{index}.png", 'x'] }.merge('index.html' => html)

    expect(code_of(zip(entries))).to eq(:zip_too_many_files)
  end

  it 'refuses paths that climb out or are absolute' do
    expect(code_of(zip('index.html' => html, '../fora.png' => 'x'))).to eq(:zip_unsafe_path)
    expect(code_of(zip('index.html' => html, 'a/../../fora.png' => 'x'))).to eq(:zip_unsafe_path)
    # rubyzip refuses to write an absolute name; the archive is patched afterwards, as a hostile tool would produce it.
    absolute = zip('index.html' => html, 'Xetc/passwd' => 'x').gsub('Xetc/passwd', '/etc/passwd')
    expect(code_of(absolute)).to eq(:zip_unsafe_path)
    expect(code_of(zip('index.html' => html, 'C:\\fora.png' => 'x'))).to eq(:zip_unsafe_path)
  end

  it 'refuses a symbolic link' do
    bytes = Zip::OutputStream.write_buffer do |stream|
      stream.put_next_entry('index.html')
      stream.write(html)
      link = Zip::Entry.new('', 'logo.png')
      link.instance_variable_set(:@ftype, :symlink)
      link.instance_variable_set(:@fstype, Zip::FSTYPE_UNIX)
      link.unix_perms = 0o777
      stream.put_next_entry(link)
      stream.write('/etc/passwd')
    end.string

    expect(code_of(bytes)).to eq(:zip_unsafe_path)
  end

  it 'refuses a zip without a page and something that is not a zip' do
    expect(code_of(zip('logo.png' => 'x'))).to eq(:zip_no_html)
    expect(code_of('não é zip')).to eq(:zip_invalid)
  end
end

# pptx (#3198): um .pptx é um zip com um XML por slide (ppt/slides/slideN.xml). Lê os slides na ordem do
# número, junta os nós de texto `a:t` de cada parágrafo `a:p` e marca o começo de cada slide. Como o docx: no
# nosso servidor, sem IA, com teto do XML descomprimido (anti zip-bomb).
class Autonomia::Agents::Knowledge::Processors::Pptx < Autonomia::Agents::Knowledge::Processors::Base
  PREFIXO = 'ppt/slides/slide'.freeze
  SUFIXO = '.xml'.freeze
  NS = { 'a' => 'http://schemas.openxmlformats.org/drawingml/2006/main' }.freeze
  MAX_DECOMPRESSED_BYTES = 50_000_000

  def extract
    ensure_gem!
    begin
      slides_text
    rescue Zip::Error => e
      raise ExtractionError, "pptx_parse_failed: #{e.message}"
    end
  end

  private

  def slides_text
    with_tempfile do |path|
      Zip::File.open(path) do |zip|
        slides = slide_entries(zip)
        raise ExtractionError, 'pptx_missing_slides' if slides.empty?
        raise ExtractionError, 'pptx_too_large' if slides.sum(&:size) > MAX_DECOMPRESSED_BYTES

        slides.each_with_index.filter_map { |entry, index| slide_text(entry, index + 1) }.join("\n\n")
      end
    end
  end

  # Os slides pelo número do nome (slide2 antes de slide10), não pela ordem do zip. `ppt/slides/_rels/...` e
  # outros arquivos da pasta ficam de fora: o meio do nome tem que ser só o número. Limitação conhecida: a ordem
  # oficial mora em ppt/presentation.xml; o PowerPoint renumera os arquivos ao salvar, mas um arquivo montado por
  # outra ferramenta pode sair fora de ordem. Slide oculto também entra.
  def slide_entries(zip)
    zip.entries.filter_map { |entry| numero_do_slide(entry.name)&.then { |numero| [numero, entry] } }
       .sort_by(&:first).map(&:last)
  end

  def numero_do_slide(nome)
    return unless nome.start_with?(PREFIXO) && nome.end_with?(SUFIXO)

    Integer(nome.delete_prefix(PREFIXO).delete_suffix(SUFIXO), 10, exception: false)
  end

  def slide_text(entry, numero)
    doc = Nokogiri::XML(entry.get_input_stream.read(MAX_DECOMPRESSED_BYTES).to_s.force_encoding('UTF-8'))
    paragrafos = doc.xpath('//a:p', NS).map { |para| para.xpath('.//a:t', NS).map(&:text).join.strip }.reject(&:empty?)
    "Slide #{numero}:\n#{paragrafos.join("\n")}" if paragrafos.any?
  end

  def ensure_gem!
    require 'zip'
  rescue LoadError
    raise UnsupportedFormat, 'pptx_support_unavailable'
  end
end

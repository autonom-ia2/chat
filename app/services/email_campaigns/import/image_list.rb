# The images an imported design still points at outside the installation (#1099) — image blocks and section
# backgrounds, never the placeholders — for the import job to copy (delivery B). data: images are listed too.
module EmailCampaigns::Import::ImageList
  module_function

  def from(document)
    sources = document.sections.flat_map do |section|
      [section.background_url, *section.columns.flat_map { |column| column.blocks.filter_map { |block| image_src(block) } }]
    end
    sources.compact.uniq.map do |src|
      { src: src, kind: src.start_with?('data:') ? 'data' : 'remote', secure: src.start_with?('https:', 'data:') }
    end
  end

  def image_src(block)
    block.attrs['src'] if block.tag == 'mj-image' && block.kind == :editable
  end
end

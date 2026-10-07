# The images an imported design still points at outside the installation (#1099) — image blocks, the custom icons of
# social links and section backgrounds, never the placeholders — for the import job to copy (delivery B). data: images
# are listed too.
module EmailCampaigns::Import::ImageList
  module_function

  def from(document)
    sources = document.sections.flat_map do |section|
      [section.background_url, *section.columns.flat_map { |column| column.blocks.flat_map { |block| image_srcs(block) } }]
    end
    sources.compact.uniq.map do |src|
      { src: src, kind: src.start_with?('data:') ? 'data' : 'remote', secure: src.start_with?('https:', 'data:') }
    end
  end

  def image_srcs(block)
    return [block.attrs['src']] if block.tag == 'mj-image' && block.kind == :editable
    return [] unless block.tag == 'mj-social'

    EmailCampaigns::Import::Limits.fragment(block.content).css('mj-social-element[src]').pluck('src')
  end
end

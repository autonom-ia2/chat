# Points a rebuilt part (#1099, delivery D) at the copies of its images: an image block takes its copy or becomes the
# "image to swap" placeholder, a section background takes its copy or carries the missing-background mark — the same
# outcomes, and the same warnings to solve, as the images of the import itself.
module EmailCampaigns::Import::PartRebuild::Images
  module_function

  def point(document, copies)
    sections = document.sections.map do |section|
      columns = section.columns.map { |column| column.with(blocks: column.blocks.map { |block| block_for(block, copies) }) }
      background(section.with(columns: columns), copies)
    end
    document.with(sections: sections)
  end

  def block_for(block, copies)
    return block unless block.tag == 'mj-image'

    copy = copies[block.attrs['src']]
    return block.with(attrs: block.attrs.merge('src' => copy)) if copy

    block.with(attrs: block.attrs.merge('src' => EmailCampaigns::Import::Placeholders::MISSING_SRC,
                                        'css-class' => EmailCampaigns::Import::Placeholders::MISSING_CLASS), kind: :missing)
  end

  def background(section, copies)
    return section if section.background_url.nil?

    copy = copies[section.background_url]
    copy ? section.with(background_url: copy) : section.with(background_url: nil, background_missing: true)
  end
end

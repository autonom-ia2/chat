# The background a text or button of an MJML design is read against (#1082, #1099): the nearest column (inner)
# background, then section, wrapper or body; white when none is set.
module EmailCampaigns::QualityGate::Background
  CONTAINERS = %w[mj-group mj-section mj-wrapper mj-body].freeze
  DEFAULT = '#ffffff'.freeze
  IMAGE_CONTAINERS = %w[mj-section mj-wrapper mj-hero].freeze

  module_function

  def of(node)
    node.ancestors.each do |parent|
      color = parent['inner-background-color'] || parent['background-color'] if parent.name == 'mj-column'
      color = parent['background-color'] if CONTAINERS.include?(parent.name)
      return color if color.present?
    end
    DEFAULT
  end

  # Whether the nearest background behind the node is an image (a section, wrapper or hero background-url not covered
  # by a column color): its color, if any, is only a fallback, so contrast cannot be judged from it.
  def image?(node)
    node.ancestors.each do |parent|
      backgrounds = image_backgrounds(parent)
      return backgrounds.first.present? if backgrounds.any?(&:present?)
    end
    false
  end

  # [image, color] a parent puts behind its content: a column only a color, a section, wrapper or hero either.
  def image_backgrounds(parent)
    return [nil, parent['inner-background-color'] || parent['background-color']] if parent.name == 'mj-column'
    return [] unless IMAGE_CONTAINERS.include?(parent.name)

    [parent['background-url'], parent['background-color']]
  end
end

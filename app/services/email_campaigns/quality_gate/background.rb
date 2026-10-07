# The background a text or button of an MJML design is read against (#1082, #1099): the nearest column (inner)
# background, then section, wrapper or body; white when none is set.
module EmailCampaigns::QualityGate::Background
  CONTAINERS = %w[mj-group mj-section mj-wrapper mj-body].freeze
  DEFAULT = '#ffffff'.freeze

  module_function

  def of(node)
    node.ancestors.each do |parent|
      color = parent['inner-background-color'] || parent['background-color'] if parent.name == 'mj-column'
      color = parent['background-color'] if CONTAINERS.include?(parent.name)
      return color if color.present?
    end
    DEFAULT
  end
end

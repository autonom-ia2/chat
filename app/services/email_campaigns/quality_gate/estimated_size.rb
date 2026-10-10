# Estimates the bytes mjml-browser would produce for an MJML design (#1099), so the server can warn about Gmail's 102 KB
# clipping without Node: a fixed document overhead, a measured overhead per component, plus the text and markup the
# components carry. Calibrated on the import fixtures: from 4% under to 15% over the real size.
module EmailCampaigns::QualityGate::EstimatedSize
  DOCUMENT = 2_000
  PER_TAG = {
    'mj-section' => 1_150, 'mj-wrapper' => 1_200, 'mj-column' => 550, 'mj-group' => 600, 'mj-text' => 360, 'mj-image' => 600,
    'mj-button' => 850, 'mj-divider' => 760, 'mj-spacer' => 220, 'mj-social' => 760, 'mj-social-element' => 900
  }.freeze
  CONTENT_FACTOR = 1.1

  module_function

  def bytes(mjml)
    doc = Nokogiri::HTML5.fragment(mjml.to_s)
    body = doc.at_css('mj-body') || doc
    overhead = body.css('*').sum { |node| PER_TAG.fetch(node.name, 0) }
    content = body.css('mj-text, mj-button, mj-social-element').sum { |node| node.inner_html.bytesize }
    attributes = body.css('*').sum { |node| node.attribute_nodes.sum { |attribute| attribute.value.bytesize } }
    (DOCUMENT + overhead + ((content + attributes) * CONTENT_FACTOR)).round
  end
end

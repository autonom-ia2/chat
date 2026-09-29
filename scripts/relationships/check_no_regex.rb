require 'json'
require 'prism'

# Parse Ruby ASTs; source is never tested against a text pattern.
results = JSON.parse($stdin.read).map do |source|
  parsed = Prism.parse(source)
  raise 'Ruby parse failed' unless parsed.success?

  found = []
  visit = lambda do |node|
    forbidden = [Prism::RegularExpressionNode, Prism::InterpolatedRegularExpressionNode].any? { |kind| node.is_a?(kind) }
    forbidden ||= node.is_a?(Prism::ConstantReadNode) && node.name.to_s == 'Regexp'
    forbidden ||= node.is_a?(Prism::ConstantPathNode) && node.name.to_s == 'Regexp'
    found << node.location.slice if forbidden
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(parsed.value)
  found
end
puts JSON.generate(results)

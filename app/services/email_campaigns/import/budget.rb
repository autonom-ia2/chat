# The ceilings one template import spends as it goes (#1099): elements and depth counted across every tree it reads —
# the page, or the MJML skeleton plus the HTML inside each of its blocks — and one deadline for the whole conversion,
# checked by the walkers as they visit nodes. Past any of them the import stops with an Error the screen can explain.
class EmailCampaigns::Import::Budget
  def initialize(seconds: EmailCampaigns::Import::Limits::TOTAL_SECONDS, clock: nil)
    @clock = clock || -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) }
    @ends_at = @clock.call + seconds
    @elements = 0
  end

  # Adds the elements of a tree to the total and measures its deepest one, without recursion.
  def count!(root)
    stack = [[root, 1]]
    until stack.empty?
      node, depth = stack.pop
      @elements += 1
      raise EmailCampaigns::Import::Error, :too_many_nodes if @elements > EmailCampaigns::Import::Limits::MAX_ELEMENTS
      raise EmailCampaigns::Import::Error, :too_deep if depth > EmailCampaigns::Import::Limits::MAX_DEPTH

      node.element_children.each { |child| stack << [child, depth + 1] }
    end
    root
  end

  # Parses client HTML found inside a block and counts it.
  def fragment!(html)
    count!(EmailCampaigns::Import::Limits.fragment(html))
  end

  def time!
    raise EmailCampaigns::Import::Error, :too_slow if @clock.call > @ends_at
  end
end

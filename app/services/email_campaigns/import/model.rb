# The importer's neutral design (#1099): what the HTML converter and the MJML reader both build, what the footer
# cleaner and the editable-area metric read, and what the emitter writes as MJML. Immutable values.
module EmailCampaigns::Import::Model
  Document = Data.define(:title, :preview, :width, :background, :sections) do
    def initialize(sections:, title: nil, preview: nil, width: 600, background: nil)
      super
    end
  end

  Section = Data.define(:columns, :background, :background_url, :padding) do
    def initialize(columns:, background: nil, background_url: nil, padding: nil)
      super
    end
  end

  Column = Data.define(:blocks, :width, :padding, :background) do
    def initialize(blocks:, width: nil, padding: nil, background: nil)
      super
    end
  end

  # tag: mj-text, mj-image, mj-button, mj-divider, mj-spacer or mj-social; content: the ending-tag markup, already
  # safe; kind: :editable, :missing (placeholder image to swap) or :unresolved (part left for the AI).
  Block = Data.define(:tag, :attrs, :content, :kind) do
    def initialize(tag:, attrs: {}, content: nil, kind: :editable)
      super(tag: tag, attrs: attrs.compact.freeze, content: content, kind: kind)
    end
  end
end

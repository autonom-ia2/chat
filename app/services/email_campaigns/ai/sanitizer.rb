module EmailCampaigns
  module Ai
    # Cleans AI-returned MJML: strips script/iframe tags, inline event handlers and dangerous URL
    # schemes in href/src attributes (javascript:/vbscript:/data:..., obfuscated with entities or whitespace),
    # guarantees the {{ unsubscribe_url }} footer is present (appends a minimal locked footer
    # when missing), turns web-search markdown citations into links (CitationLinks) and stores
    # canonical MJML — explicit close tags, flat mj-attributes (MjmlCanonicalizer, #1074). Idempotent.
    class Sanitizer
      UNSUBSCRIBE_PLACEHOLDER = /\{\{\s*unsubscribe_url\s*\}\}/
      SAFE_SCHEMES = %w[http https mailto tel].freeze
      # Matches href/src attribute values (quoted, single-quoted or bare).
      URL_ATTR_REGEX = /(\b(?:href|src)\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i
      # Safety-net footer (legal line + unsubscribe). Brand-neutral on purpose: it is appended to any
      # account's e-mail, so it carries no social profiles or address of a specific company.
      FALLBACK_FOOTER = <<~MJML.freeze
        <mj-section css-class="footer-locked" background-color="#f4f4f4" padding="20px 16px">
          <mj-column>
            <mj-text font-size="12px" color="#6b7280" align="center" line-height="1.6">
              Você recebeu este e-mail porque está em nossa lista de contatos.<br/>
              <a href="{{ unsubscribe_url }}" style="color:#6b7280;">Cancelar inscrição</a>
            </mj-text>
          </mj-column>
        </mj-section>
      MJML

      def initialize(mjml)
        @mjml = mjml.to_s
      end

      def perform
        linked = CitationLinks.call(strip_dangerous(@mjml))
        EmailCampaigns::MjmlCanonicalizer.call(ensure_footer(neutralize_url_attrs(linked)))
      end

      private

      # Fixed-point strip: re-run the tag/handler removals until the string stops changing, so a
      # split payload like `<scr<iframe></iframe>ipt>` that re-assembles into `<script>` after the
      # first pass is caught on the next pass.
      def strip_dangerous(mjml)
        loop do
          cleaned = mjml
                    .gsub(%r{<script\b[^>]*>.*?</script>}mi, '')
                    .gsub(%r{</?script\b[^>]*>}i, '')
                    .gsub(%r{<iframe\b[^>]*>.*?</iframe>}mi, '')
                    .gsub(%r{</?iframe\b[^>]*>}i, '')
                    .gsub(/\son\w+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)/i, '')
          return cleaned if cleaned == mjml

          mjml = cleaned
        end
      end

      # Neutralize URL attributes by SCHEME: decode basic HTML entities and strip whitespace/control
      # chars inside the scheme, then block (replace with #) any href/src whose scheme is not in
      # SAFE_SCHEMES. Covers javascript:, vbscript:, data:text/html, including entity- (&colon;,
      # &#58;) and whitespace-obfuscated (java\tscript:) variants. Idempotent.
      def neutralize_url_attrs(mjml)
        mjml.gsub(URL_ATTR_REGEX) do
          prefix = Regexp.last_match(1)
          value = Regexp.last_match(2) || Regexp.last_match(3) || Regexp.last_match(4) || ''
          safe_url_attr?(value) ? Regexp.last_match(0) : %(#{prefix}"#")
        end
      end

      def safe_url_attr?(value)
        scheme = scheme_of(value)
        # No scheme (relative URL, anchor, placeholder like {{ unsubscribe_url }}) is allowed.
        scheme.nil? || SAFE_SCHEMES.include?(scheme)
      end

      # Extract the URL scheme after decoding entities and removing whitespace/control chars that
      # attackers insert to slip a scheme past a naive check (e.g. `java\tscript:`, `javascript&colon;`).
      def scheme_of(value)
        decoded = decode_entities(value)
        cleaned = decoded.gsub(/[[:space:]\x00-\x20]/, '')
        return nil unless cleaned =~ /\A([a-zA-Z][a-zA-Z0-9+.\-]*):/

        Regexp.last_match(1).downcase
      end

      def decode_entities(value)
        value
          .gsub(/&colon;?/i, ':')
          .gsub(/&Tab;?/i, "\t")
          .gsub(/&NewLine;?/i, "\n")
          .gsub(/&#x0*([0-9a-f]+);?/i) { [Regexp.last_match(1).to_i(16)].pack('U') }
          .gsub(/&#0*(\d+);?/) { [Regexp.last_match(1).to_i].pack('U') }
      end

      # Guarantee the email ends with the canonical LOCKED footer carrying the unsubscribe link.
      # We require a footer-locked mj-section that ACTUALLY contains {{ unsubscribe_url }} — not the
      # two markers anywhere independently — so a stray footer-locked class plus an unrelated
      # placeholder can't pass. Otherwise append the fallback (which is exactly such a block) right
      # before the (case/whitespace-tolerant) </mj-body>. Idempotent: well-formed output already has
      # the locked footer, so nothing is appended.
      BODY_CLOSE = %r{</mj-body\s*>}i
      LOCKED_FOOTER_BLOCK = %r{<mj-section\b[^>]*footer-locked[^>]*>(.*?)</mj-section>}mi

      def ensure_footer(mjml)
        return mjml if locked_footer_with_unsubscribe?(mjml)
        return mjml.sub(BODY_CLOSE) { |close| "#{FALLBACK_FOOTER}#{close}" } if mjml.match?(BODY_CLOSE)

        mjml + FALLBACK_FOOTER
      end

      # A footer-locked mj-section whose own content carries the unsubscribe placeholder. mj-sections
      # don't nest, so the non-greedy block capture is a safe approximation of "this section".
      def locked_footer_with_unsubscribe?(mjml)
        mjml.scan(LOCKED_FOOTER_BLOCK).any? { |(inner)| inner.match?(UNSUBSCRIBE_PLACEHOLDER) }
      end
    end
  end
end

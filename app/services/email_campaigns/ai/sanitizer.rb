module EmailCampaigns
  module Ai
    # Cleans AI-returned MJML: strips script/iframe tags, inline event handlers and dangerous URL
    # schemes in href/src attributes (javascript:/vbscript:/data:..., obfuscated with entities or whitespace),
    # turns web-search markdown citations into links (CitationLinks), guarantees exactly one locked
    # footer with the {{ unsubscribe_url }} link (LockedFooter, #1081) and stores canonical MJML —
    # explicit close tags, flat mj-attributes (MjmlCanonicalizer, #1074). Idempotent.
    class Sanitizer
      SAFE_SCHEMES = %w[http https mailto tel].freeze
      # Matches href/src attribute values (quoted, single-quoted or bare).
      URL_ATTR_REGEX = /(\b(?:href|src)\s*=\s*)(?:"([^"]*)"|'([^']*)'|([^\s>]+))/i
      # Safety-net footer appended when the e-mail has no unsubscribe link: the shared one (lockedFooter.json).
      FALLBACK_FOOTER = EmailCampaigns::LockedFooter::MJML

      def initialize(mjml)
        @mjml = mjml.to_s
      end

      def perform
        linked = CitationLinks.call(strip_dangerous(@mjml))
        EmailCampaigns::LockedFooter.ensure(neutralize_url_attrs(linked))
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
    end
  end
end

module EmailCampaigns
  # Thin Liquid wrapper for campaign subject/body. Supports {{ contact.name }},
  # {{ contact.email }}, the pt_BR convenience aliases {{ nome }} / {{ email }},
  # the recipient's imported custom_data columns and {{ unsubscribe_url }}.
  #
  # html: true (body and preheader, #999 review B8) escapes the recipient's values
  # (CGI.escapeHTML), so a name or spreadsheet cell is shown as text and never becomes markup.
  # The subject is plain text and is rendered without escaping.
  class TemplateRenderer
    # inert_unsubscribe: render {{ unsubscribe_url }} as '#' so a test-send click can
    # never unsubscribe a real contact.
    def initialize(recipient, inert_unsubscribe: false)
      @recipient = recipient
      @inert_unsubscribe = inert_unsubscribe
    end

    def render(template, html: false)
      return '' if template.blank?

      Liquid::Template.parse(template).render(html ? escaped_drops : drops)
    rescue Liquid::Error
      template
    end

    private

    def drops
      @drops ||= begin
        name = @recipient.name.to_s
        email = @recipient.email.to_s
        @recipient.custom_data.to_h.merge(
          'contact' => { 'name' => name, 'email' => email },
          'nome' => name,
          'email' => email,
          'unsubscribe_url' => @inert_unsubscribe ? '#' : EmailCampaigns::Unsubscribe::Token.url(@recipient)
        )
      end
    end

    def escaped_drops
      @escaped_drops ||= escape(drops)
    end

    def escape(value)
      case value
      when Hash then value.transform_values { |item| escape(item) }
      when String then CGI.escapeHTML(value)
      else value
      end
    end
  end
end

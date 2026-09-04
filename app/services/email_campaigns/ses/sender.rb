module EmailCampaigns
  module Ses
    # Sends a single email through SES from a verified sender identity. Powers the human
    # smoke test now and campaign delivery in later waves. Returns the SES MessageId.
    class Sender
      def initialize(identity)
        @identity = identity
        @client = Client.new
      end

      def deliver(to:, subject:, html_body:, text_body: nil, from_email: nil, reply_to: nil, headers: nil)
        raise Error, "identity #{@identity.domain} is not verified" unless @identity.usable?

        response = @client.send_email(
          from: resolve_from(from_email), to: to, subject: subject,
          html_body: html_body, text_body: text_body, reply_to: reply_to,
          configuration_set: configuration_set_name, headers: headers
        )
        response['MessageId']
      end

      private

      # Identities provisionadas antes do campo existir ficaram com ses_configuration_set nulo e
      # passaram a enviar SEM configuration set — o SES entao nao publica Delivery/Bounce/
      # Complaint para lugar nenhum. O campo e um override; o default do sistema e a fonte.
      def configuration_set_name
        @identity.ses_configuration_set.presence || EmailCampaigns::Config.configuration_set_name
      end

      def resolve_from(from_email)
        from_email.presence || @identity.from_email.presence || "no-reply@#{@identity.domain}"
      end
    end
  end
end

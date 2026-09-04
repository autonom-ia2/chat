module EmailCampaigns
  module Ses
    # Ensures the SES configuration set publishes DELIVERY/BOUNCE/COMPLAINT to an SNS topic that
    # our public webhook is subscribed to. SNS side uses aws-sdk-sns; SES side stays gem-free.
    # Invoked OPERATIONALLY (rake/console at enable time), not per request.
    class EventDestinationEnsurer
      DESTINATION_NAME = 'autonomia-sns-events'.freeze
      EVENT_TYPES = %w[DELIVERY BOUNCE COMPLAINT].freeze
      PUBLISH_SID = 'AllowSESPublish'.freeze

      def perform
        EmailCampaigns::Ses::ConfigurationSetEnsurer.new.perform
        topic_arn = ensure_topic
        allow_ses_publish(topic_arn)
        subscribe_webhook(topic_arn)
        put_event_destination(topic_arn)
        topic_arn
      end

      private

      def sns
        @sns ||= Aws::SNS::Client.new(
          region: EmailCampaigns::Config.region,
          access_key_id: EmailCampaigns::Config.access_key_id,
          secret_access_key: EmailCampaigns::Config.secret_access_key
        )
      end

      def ensure_topic
        sns.create_topic(name: EmailCampaigns::Sns::Config.topic_name).topic_arn
      end

      # Without this statement SES is denied on Publish and every Delivery/Bounce/Complaint is
      # dropped silently — the topic exists, the destination exists, and no event ever arrives.
      # Merged into the existing policy (never replaced) so the topic keeps its owner statement.
      def allow_ses_publish(topic_arn)
        policy = current_policy(topic_arn)
        statements = Array(policy['Statement'])
        return if statements.any? { |statement| statement['Sid'] == PUBLISH_SID }

        policy['Version'] ||= '2012-10-17'
        policy['Statement'] = statements + [publish_statement(topic_arn)]
        sns.set_topic_attributes(topic_arn: topic_arn, attribute_name: 'Policy', attribute_value: policy.to_json)
      end

      def current_policy(topic_arn)
        raw = sns.get_topic_attributes(topic_arn: topic_arn).attributes['Policy']
        JSON.parse(raw.to_s)
      rescue JSON::ParserError
        {}
      end

      def publish_statement(topic_arn)
        {
          'Sid' => PUBLISH_SID,
          'Effect' => 'Allow',
          'Principal' => { 'Service' => 'ses.amazonaws.com' },
          'Action' => 'sns:Publish',
          'Resource' => topic_arn,
          'Condition' => { 'StringEquals' => { 'AWS:SourceAccount' => topic_arn.split(':')[4] } }
        }
      end

      def subscribe_webhook(topic_arn)
        sns.subscribe(topic_arn: topic_arn, protocol: webhook_protocol,
                      endpoint: EmailCampaigns::Sns::Config.webhook_url, return_subscription_arn: true)
      end

      def webhook_protocol
        EmailCampaigns::Sns::Config.webhook_url.start_with?('https') ? 'https' : 'http'
      end

      # gem-free SES: PUT a configuration-set event destination pointing DELIVERY/BOUNCE/
      # COMPLAINT to the SNS topic.
      def put_event_destination(topic_arn)
        EmailCampaigns::Ses::Client.new.put_configuration_set_event_destination(
          configuration_set: EmailCampaigns::Config.configuration_set_name,
          destination_name: DESTINATION_NAME,
          sns_topic_arn: topic_arn,
          event_types: EVENT_TYPES
        )
      end
    end
  end
end

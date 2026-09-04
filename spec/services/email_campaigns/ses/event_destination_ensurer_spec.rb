require 'rails_helper'

RSpec.describe EmailCampaigns::Ses::EventDestinationEnsurer do
  let(:topic_arn) { 'arn:aws:sns:us-east-1:354307071110:autonomia-email-campaign-events' }
  let(:sns) { instance_double(Aws::SNS::Client) }
  let(:ses_client) { instance_double(EmailCampaigns::Ses::Client) }
  let(:policy_writes) { [] }
  let(:configuration_set_ensurer) { instance_double(EmailCampaigns::Ses::ConfigurationSetEnsurer, perform: true) }

  before do
    allow(Aws::SNS::Client).to receive(:new).and_return(sns)
    allow(EmailCampaigns::Ses::Client).to receive(:new).and_return(ses_client)
    allow(EmailCampaigns::Ses::ConfigurationSetEnsurer).to receive(:new).and_return(configuration_set_ensurer)
    allow(sns).to receive(:create_topic).and_return(
      instance_double(Aws::SNS::Types::CreateTopicResponse, topic_arn: topic_arn)
    )
    allow(sns).to receive(:set_topic_attributes) { |args| policy_writes << args }
    allow(sns).to receive(:subscribe)
    allow(ses_client).to receive(:put_configuration_set_event_destination)
  end

  def default_policy
    { 'Version' => '2012-10-17', 'Statement' => [{ 'Sid' => 'owner' }] }.to_json
  end

  def stub_policy(policy)
    allow(sns).to receive(:get_topic_attributes).and_return(
      instance_double(Aws::SNS::Types::GetTopicAttributesResponse, attributes: { 'Policy' => policy })
    )
  end

  def published_policy
    JSON.parse(policy_writes.last[:attribute_value])
  end

  # Without an explicit Allow for ses.amazonaws.com, SES is denied on Publish and every
  # Delivery/Bounce/Complaint is dropped: the topic and the destination both look healthy
  # while no event ever reaches the webhook.
  it 'grants SES permission to publish on the topic' do
    stub_policy(default_policy)

    described_class.new.perform

    statement = published_policy['Statement'].find { |item| item['Sid'] == 'AllowSESPublish' }
    expect(statement).to include(
      'Effect' => 'Allow',
      'Principal' => { 'Service' => 'ses.amazonaws.com' },
      'Action' => 'sns:Publish',
      'Resource' => topic_arn
    )
    expect(statement.dig('Condition', 'StringEquals', 'AWS:SourceAccount')).to eq('354307071110')
  end

  it 'keeps the statements the topic already had' do
    stub_policy(default_policy)

    described_class.new.perform

    expect(published_policy['Statement'].map { |item| item['Sid'] }).to eq(%w[owner AllowSESPublish])
  end

  it 'does not rewrite the policy when SES is already allowed' do
    stub_policy({ 'Version' => '2012-10-17', 'Statement' => [{ 'Sid' => 'AllowSESPublish' }] }.to_json)

    described_class.new.perform

    expect(sns).not_to have_received(:set_topic_attributes)
  end

  it 'subscribes the webhook and points the configuration set at the topic' do
    stub_policy(default_policy)

    expect(described_class.new.perform).to eq(topic_arn)

    expect(sns).to have_received(:subscribe).with(
      hash_including(topic_arn: topic_arn, protocol: 'https', endpoint: EmailCampaigns::Sns::Config.webhook_url)
    )
    expect(ses_client).to have_received(:put_configuration_set_event_destination).with(
      hash_including(sns_topic_arn: topic_arn, event_types: %w[DELIVERY BOUNCE COMPLAINT])
    )
  end
  # Uma leitura ilegivel nao pode virar "policy vazia": escrever so o nosso statement apagaria
  # o statement default do dono do topico.
  it 'refuses to overwrite the policy when it cannot be read' do
    stub_policy('not json')

    expect { described_class.new.perform }.to raise_error(EmailCampaigns::Ses::Error, /unreadable policy/)
    expect(sns).not_to have_received(:set_topic_attributes)
  end
end

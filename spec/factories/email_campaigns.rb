FactoryBot.define do
  factory :email_sender_identity do
    account
    domain { 'example.org' }
    from_email { 'sender@example.org' }
    provider { 'ses' }
    status { :verified }
  end

  factory :email_campaign do
    account
    sender_identity { association :email_sender_identity, account: account }
    name { 'Hygiene regression' }
    subject { 'Example' }
    body_html { '<p>Example</p>' }
    from_email { 'sender@example.org' }
  end

  factory :email_campaign_recipient do
    email_campaign
    sequence(:email) { |n| "recipient#{n}@example.org" }
  end
end

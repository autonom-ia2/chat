# Offline import with simulated atomic persistence. No Rails, ActiveRecord or database is loaded.
ENV['MT_NO_PLUGINS'] = '1'
require 'minitest/autorun'
require 'minitest/mock'
require 'active_support'
require 'active_support/core_ext'
require 'uri'
module EmailCampaigns; end
module CampaignImports; end
require_relative '../../../app/services/campaign_imports/parser'
require_relative '../../../app/services/campaign_imports/header_mapper'
require_relative '../../../app/services/email_campaigns/email_normalizer'
require_relative '../../../app/services/email_campaigns/recipient_importer'

CampaignImports::Config = Class.new do
  def self.supported_formats
    ['csv']
  end
end
EmailCampaign = Class.new
EmailCampaign::EMAIL_REGEX = URI::MailTo::EMAIL_REGEXP
EmailSuppression = Class.new do
  def self.suppressed_set_for(*)
    Set.new
  end
end
EmailCampaignRecipient = Struct.new(:attributes) do
  class << self
    attr_accessor :rows

    def insert_all!(records)
      rows.concat(records)
    end
  end

  def initialize(**attributes)
    super(attributes.stringify_keys)
  end

  def valid?(*)
    true
  end
end
EmailCampaignImportIssue = Class.new do
  class << self
    attr_accessor :rows

    def insert_all!(records)
      records.each do |record|
        raw = record.fetch(:raw_address)
        raise 'unpersistable text' unless raw.valid_encoding? && raw.exclude?("\0") && raw.length <= 320
      end
      rows.concat(records)
    end
  end
end
module ActiveRecord; end
ActiveRecord::Base = Class.new do
  def self.transaction
    yield
  rescue StandardError
    EmailCampaignRecipient.rows.clear
    EmailCampaignImportIssue.rows.clear
    raise
  end
end

class RecipientImportEncodingTest < Minitest::Test
  def setup
    EmailCampaignRecipient.rows = []
    EmailCampaignImportIssue.rows = []
    existing = Minitest::Mock.new
    existing.expect(:pluck, [], [:email])
    @campaign = Minitest::Mock.new
    @campaign.expect(:account, Object.new)
    @campaign.expect(:email_campaign_recipients, existing)
    @campaign.expect(:id, 42)
    @campaign.expect(:refresh_counters!, nil)
    @campaign.expect(:with_lock, nil) do |mode, &operation|
      assert_equal 'FOR KEY SHARE', mode
      ActiveRecord::Base.transaction(&operation)
      true
    end
  end

  def test_nul_csv_does_not_roll_back_valid_row_or_disappear_from_counts
    csv = "name,email\nGood,User+Tag@example.org\nBad,bad\0mail@example.org\n"
    result = EmailCampaigns::RecipientImporter.new(@campaign, csv, filename: 'nul.csv').perform
    assert_equal({ imported: 1, invalid: 1, total: 2 }, result.to_h.slice(:imported, :invalid, :total))
    assert_equal ['user+tag@example.org'], EmailCampaignRecipient.rows.pluck('email')
    assert_equal 'bad\\x00mail@example.org', EmailCampaignImportIssue.rows.fetch(0).fetch(:raw_address)
    assert_equal ['invalid_email', 3], EmailCampaignImportIssue.rows.fetch(0).values_at(:reason_code, :row_number)
    @campaign.verify
  end

  def test_invalid_utf8_parsed_row_preserves_valid_commit_and_bounded_issue
    # The parser seam simulates a decoded spreadsheet/parser row containing invalid UTF-8.
    rows = [
      CampaignImports::Parser::ParsedRow.new(row_number: 2, values: ['Good', 'User+Tag@example.org']),
      CampaignImports::Parser::ParsedRow.new(row_number: 3, values: ['', "bad\xFF#{'x' * 400}@example.org"])
    ]
    parsed = CampaignImports::Parser::ParsedFile.new(headers: %w[name email], format: 'csv', rows: rows)
    parser = Minitest::Mock.new
    parser.expect(:perform, parsed)
    CampaignImports::Parser.stub(:new, parser) do
      result = EmailCampaigns::RecipientImporter.new(@campaign, '', filename: 'invalid.csv').perform
      assert_equal({ imported: 1, invalid: 1, total: 2 }, result.to_h.slice(:imported, :invalid, :total))
    end
    assert_equal ['user+tag@example.org'], EmailCampaignRecipient.rows.pluck('email')
    issue = EmailCampaignImportIssue.rows.fetch(0)
    assert_equal ['invalid_email', 3], issue.values_at(:reason_code, :row_number)
    assert_equal "bad\\xFF#{'x' * 313}", issue.fetch(:raw_address)
    assert_predicate issue.fetch(:raw_address), :valid_encoding?
    @campaign.verify
  end
end

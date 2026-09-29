# Standalone suite: no Rails boot, database, Redis, or network.
require 'active_support/all'
require 'uri'
module Relationships; end
require_relative '../../../app/services/relationships/configuration'
require_relative '../../../app/services/relationships/value_validator'

RSpec.describe Relationships::ValueValidator do
  # Reuse historical fixture metadata without introducing a pattern.
  let(:legacy_pattern) do
    File.readlines(File.expand_path('../../jobs/inboxes/update_widget_pre_chat_custom_fields_job_spec.rb', __dir__))
        .find { |line| line.include?("'regex_pattern' =>") }.split("'")[3]
  end

  let(:definition) { Struct.new(:attribute_display_type, :regex_pattern, :attribute_values).new(type, pattern, options) }
  let(:validator) { described_class.new(definition) }
  let(:pattern) { nil }
  let(:options) { [] }
  let(:type) { 'number' }

  it 'accepts zero and nil but rejects empty strings and non-finite numbers' do
    expect { validator.validate!(0) }.not_to raise_error
    expect { validator.validate!(nil) }.not_to raise_error
    ['', '0', Float::INFINITY, Float::NAN].each do |value|
      expect { validator.validate!(value) }.to raise_error(Relationships::Configuration::Invalid)
    end
  end

  context 'with checkbox' do
    let(:type) { 'checkbox' }

    it 'accepts false without coercing strings' do
      expect { validator.validate!(false) }.not_to raise_error
      expect { validator.validate!('false') }.to raise_error(Relationships::Configuration::Invalid)
    end
  end

  context 'with date' do
    let(:type) { 'date' }

    it 'requires a valid date-only value' do
      expect { validator.validate!('2026-09-29') }.not_to raise_error
      %w[2026-02-30 2026-09-29T00:00:00Z 09/29/2026].each do |value|
        expect { validator.validate!(value) }.to raise_error(Relationships::Configuration::Invalid)
      end
    end
  end

  context 'with link' do
    let(:type) { 'link' }

    it 'allows web URLs and rejects active or malformed schemes' do
      expect { validator.validate!('https://example.test/path') }.not_to raise_error
      ['javascript:alert(1)', 'file:///etc/passwd', 'https://', false].each do |value|
        expect { validator.validate!(value) }.to raise_error(Relationships::Configuration::Invalid)
      end
    end
  end

  context 'with list' do
    let(:type) { 'list' }
    let(:options) { %w[CEO CFO] }

    it 'accepts only an explicit option' do
      expect { validator.validate!('CEO') }.not_to raise_error
      expect { validator.validate!('ceo') }.to raise_error(Relationships::Configuration::Invalid)
    end
  end

  context 'with text and regex' do
    let(:type) { 'text' }
    let(:pattern) { legacy_pattern }

    it 'rejects legacy validation including clearing without interpreting the metadata' do
      expect { validator.validate!(nil) }.to raise_error(Relationships::Configuration::Invalid)
      expect { validator.validate!('ceo') }.to raise_error(Relationships::Configuration::Invalid)
    end
  end
end

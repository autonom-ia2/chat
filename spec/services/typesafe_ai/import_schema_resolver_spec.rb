require 'rails_helper'

RSpec.describe TypesafeAi::ImportSchemaResolver do
  let(:client) { instance_double(TypesafeAi::Client) }
  let(:resolver) { described_class.new(client: client, model: 'jev-1.13.0') }
  let(:candidate) do
    {
      id: 'table_0_candidate_0', table_name: 'Base', header_row_number: 1,
      headers: ['SEGURADO', 'MAIL PRINCIPAL', 'BROKER'],
      profiles: [
        { non_blank_count: 2, total_valid_emails: 0 },
        { non_blank_count: 2, total_valid_emails: 2 },
        { non_blank_count: 2, total_valid_emails: 0 }
      ]
    }
  end

  it 'resolves email/name mapping and certification in one Jev request' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.97 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.9 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.99 }
        }
      }
    )

    result = resolver.resolve(candidate)

    expect(result.slice(:candidate_id, :email_index, :name_index)).to eq(
      candidate_id: candidate[:id], email_index: 1, name_index: 0
    )
    expect(result[:metadata]).to include(
      'model' => 'jev-1.13.0', 'email_confidence' => 0.97,
      'name_confidence' => 0.9, 'schema_probability' => 0.99
    )
    expect(client).to have_received(:evaluate).with(hash_including(state: hash_excluding(:sheet))).once
  end

  it 'accepts an absent name because only email is mandatory' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.9 },
          'name_column' => { 'type' => 'choice', 'choice' => 'none', 'confidence' => 0.79 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.9 }
        }
      }
    )

    expect(resolver.resolve(candidate)[:name_index]).to be_nil
  end

  it 'separates column evidence from row quality when valid addresses are rare' do
    sparse = candidate.deep_dup
    sparse[:profiles][1] = {
      total_rows: 120, sampled_rows: 50, non_blank_count: 50, email_like_count: 0,
      total_valid_emails: 1, examples: ['[email address]', 'aaa-aaaaa-0']
    }
    expect(client).to receive(:evaluate) do |request|
      expect(request.fetch(:state).fetch(:profiles)[1]).to eq(contains_valid_email: true, examples: ['[email address]'])
      expect(request.fetch(:questions).fetch(:email_column).fetch(:criteria).fetch('column_1').fetch(:profile))
        .to eq(contains_valid_email: true, examples: ['[email address]'])
      expect(request.to_json).not_to include('total_rows', 'email_like_count', 'non_blank_count', 'total_valid_emails')
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.99 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.99 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.99 }
        }
      }
    end

    expect(resolver.resolve(sparse)).to include(email_index: 1, name_index: 0)
  end

  it 'imports a reliable email column while leaving an uncertain optional name unmapped' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.95 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.79 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.95 }
        }
      }
    )

    expect(resolver.resolve(candidate)).to include(email_index: 1, name_index: nil)
  end

  it 'rejects a Jev email choice that has no deterministic email evidence below the header' do
    no_email_evidence = candidate.deep_dup
    no_email_evidence[:profiles][1][:total_valid_emails] = 0
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.99 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.9 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.99 }
        }
      }
    )

    expect { resolver.resolve(no_email_evidence) }.to raise_error(described_class::Error, 'no_valid_emails')
  end

  it 'rejects a mapping when Jev itself does not certify the schema' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.99 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.99 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.49 }
        }
      }
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'schema_not_resolved')
  end

  it 'accepts decisive column choices when the independent schema answer is affirmative' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 1.0 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 1.0 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.72 }
        }
      }
    )

    expect(resolver.resolve(candidate)).to include(email_index: 1, name_index: 0)
  end

  it 'rejects a low-confidence answer instead of guessing the recipient column' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.55 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.99 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.99 }
        }
      }
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'schema_not_resolved')
  end

  it 'rejects an out-of-range model column instead of trusting malformed output' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_99', 'confidence' => 1.0 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 1.0 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 1.0 }
        }
      }
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
  end

  it 'reports unresolved ambiguity when Jev chooses none despite address evidence' do
    allow(client).to receive(:evaluate).and_return(
      {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'none', 'confidence' => 0.9 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.7 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.2 }
        }
      }
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'schema_not_resolved')
  end

  [
    ['model', 'unexpected-model'],
    ['answers', 'email_column', 'type', 'noul'],
    ['answers', 'email_column', 'confidence', '0.99'],
    ['answers', 'name_column', 'confidence', 1.01],
    ['answers', 'schema_valid', 'noul', -0.1],
    ['answers', 'email_column', 'choice', 'column_01']
  ].each do |path_and_value|
    it "rejects malformed #{path_and_value[0...-1].join('.')}" do
      response = {
        'model' => 'jev-1.13.0',
        'answers' => {
          'email_column' => { 'type' => 'choice', 'choice' => 'column_1', 'confidence' => 0.99 },
          'name_column' => { 'type' => 'choice', 'choice' => 'column_0', 'confidence' => 0.99 },
          'schema_valid' => { 'type' => 'noul', 'noul' => 0.99 }
        }
      }
      path = path_and_value[0...-1]
      response.dig(*path[0...-1])[path.last] = path_and_value.last if path.size > 1
      response[path.first] = path_and_value.last if path.size == 1
      allow(client).to receive(:evaluate).and_return(response)
      expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
    end
  end
end

require 'rails_helper'

RSpec.describe TypesafeAi::AudienceSchemaResolver, :aggregate_failures do
  let(:client) { instance_double(TypesafeAi::Client) }
  let(:resolver) { described_class.new(client: client, model: 'jev-1.13.0') }
  let(:candidate) do
    {
      headers: ['Segurado', 'Fone 1', 'Corretora'], header_row_number: 1,
      profiles: [
        { non_blank_count: 2, valid_phone_count: 0, valid_email_count: 0, examples: ['Aaa Aaaaa'] },
        { non_blank_count: 2, valid_phone_count: 2, valid_email_count: 0, examples: ['(00) 00000-0000'] },
        { non_blank_count: 2, valid_phone_count: 0, valid_email_count: 0, examples: ['Aaaaaaaaa Aaaa'] }
      ]
    }
  end

  def answer(choice, confidence = 0.95)
    { 'type' => 'choice', 'choice' => choice, 'confidence' => confidence }
  end

  def response(model: 'jev-1.13.0', **answers)
    { 'model' => model, 'answers' => answers.transform_keys { |key| "#{key}_column" }.merge('schema_valid' => { 'type' => 'noul', 'noul' => 0.9 }) }
  end

  it 'asks the four targets plus schema validity in one request and returns index and confidence per target' do
    allow(client).to receive(:evaluate).and_return(
      response(phone: answer('column_1'), email: answer('none', 0.9), name: answer('column_0'), company: answer('column_2', 0.6))
    )

    result = resolver.resolve(candidate)

    expect(result[:targets]).to eq(
      phone: { index: 1, confidence: 0.95 }, email: { index: nil, confidence: 0.9 },
      name: { index: 0, confidence: 0.95 }, company: { index: 2, confidence: 0.6 }
    )
    expect(result).to include(schema_probability: 0.9, model: 'jev-1.13.0')
    expect(client).to have_received(:evaluate).with(
      hash_including(model: 'jev-1.13.0', questions: hash_including(:phone_column, :email_column, :name_column, :company_column, :schema_valid))
    ).once
  end

  describe 'share_hint (customer_base reading, #1246)' do
    before do
      allow(client).to receive(:evaluate).and_return(
        response(phone: answer('column_1'), email: answer('none'), name: answer('column_0'), company: answer('none'))
      )
    end

    it 'sends the share of valid values and the phone question that trusts it when on' do
      described_class.new(client: client, model: 'jev-1.13.0', share_hint: true).resolve(candidate)

      expect(client).to have_received(:evaluate) do |state:, questions:, **|
        expect(state[:profiles][1]).to include(valid_phone_share: 1.0, valid_email_share: 0.0)
        expect(state[:task]).to eq(described_class::STATE_TASK_WITH_SHARE)
        expect(questions[:phone_column][:instructions]).to eq(described_class::PHONE_WITH_SHARE)
      end
    end

    it 'sends the request every account has when off' do
      resolver.resolve(candidate)

      expect(client).to have_received(:evaluate) do |state:, questions:, **|
        expect(state[:profiles][1].keys).to eq(%i[non_blank_count valid_phone_count valid_email_count examples])
        expect(state[:task]).to eq(described_class::STATE_TASK)
        expect(questions[:phone_column][:instructions]).to eq(described_class::TARGETS[:phone])
      end
    end
  end

  it 'rejects an answer from another model than the pinned one' do
    allow(client).to receive(:evaluate).and_return(
      response(model: 'jev-latest', phone: answer('column_1'), email: answer('none'), name: answer('column_0'), company: answer('none'))
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
  end

  it 'rejects a choice outside the table' do
    allow(client).to receive(:evaluate).and_return(
      response(phone: answer('column_9'), email: answer('none'), name: answer('column_0'), company: answer('none'))
    )

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'typesafe_invalid_response')
  end

  it 'turns a client failure into a sanitized code' do
    allow(client).to receive(:evaluate).and_raise(TypesafeAi::Client::Error.new('typesafe_unavailable'))

    expect { resolver.resolve(candidate) }.to raise_error(described_class::Error, 'typesafe_unavailable')
  end
end

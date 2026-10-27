require 'rails_helper'

# #2277: what the reader model answers is checked against the batch it read.
RSpec.describe ConversationAudience::Reader do
  let(:account) { create(:account) }
  let(:search) do
    create_search(plan: { 'rule' => 'Pediu cotação', 'sure' => 'pediu', 'likely' => 'parece', 'near' => 'quase' })
  end
  let(:client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:batch) { ConversationAudienceBatch.create!(search: search, number: 1, conversation_ids: [10, 11, 12]) }
  let(:texts) { { 10 => "=== CONVERSA 10\n", 11 => "=== CONVERSA 11\n", 12 => "=== CONVERSA 12\n" } }

  def create_search(**attributes)
    ConversationAudienceSearch.create!(account: account, request: 'quem cotou', period: '30d', **attributes)
  end

  def answer(people)
    { text: { pessoas: people }.to_json, usage: { 'input_tokens' => 100, 'output_tokens' => 20 } }
  end

  def person(conversa, grupo)
    { conversa: conversa, grupo: grupo, motivo: "Cotou (#{conversa})", provas: ['[10-01T10:00]'] }
  end

  before { allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(client) }

  it 'reads only the digits of the conversation number, drops numbers outside the batch and keeps the strongest group' do
    allow(client).to receive(:create).and_return(
      answer([person('CONVERSA 10', 'fora'), person('10', 'certeza'), person('11', 'provavel'), person('99', 'certeza')])
    )

    result = described_class.new(search, credential: { api_key: 'k' }).call([[batch, texts]]).first

    expect(result.error).to be_nil
    expect(result.people.map { |item| [item[:conversation_id], item[:group]] }).to contain_exactly([10, 'certeza'], [11, 'provavel'])
    expect(result.usage).to include('input_tokens' => 100)
  end

  it 'sends the plan rule and the transcripts to the reader model on the account key' do
    allow(client).to receive(:create).and_return(answer([]))

    described_class.new(search, credential: { api_key: 'k' }).call([[batch, texts]])

    expect(client).to have_received(:create).with(
      hash_including(model: 'gpt-6-luna', reasoning_effort: 'medium', input: texts.values.join("\n"),
                     instructions: include('Regra do público: Pediu cotação'))
    )
    expect(Crm::Ai::ResponsesClient).to have_received(:new).with(hash_including(credential: { api_key: 'k' }, max_retries: 1))
  end

  it 'keeps the usage of an answer it could not read, so the call is charged' do
    allow(client).to receive(:create).and_return(text: 'não é json', usage: { 'input_tokens' => 50 })

    result = described_class.new(search, credential: { api_key: 'k' }).call([[batch, texts]]).first

    expect(result.error).to be_a(JSON::ParserError)
    expect(result.usage).to eq('input_tokens' => 50)
  end

  it 'keeps a network failure with its batch, without losing the other batches' do
    other = ConversationAudienceBatch.create!(search: search, number: 2, conversation_ids: [13])
    allow(client).to receive(:create) do |args|
      raise Errno::EHOSTUNREACH if args[:input].include?('CONVERSA 13')

      answer([person('10', 'certeza')])
    end

    results = described_class.new(search, credential: { api_key: 'k' }).call([[batch, texts], [other, { 13 => "=== CONVERSA 13\n" }]])

    expect(results.first.people.size).to eq(1)
    expect(results.last.error).to be_a(Errno::EHOSTUNREACH)
  end

  it 'returns the error of a batch the AI did not answer, without raising' do
    allow(client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('boom', status: 503))

    result = described_class.new(search, credential: { api_key: 'k' }).call([[batch, texts]]).first

    expect(result.error).to be_a(Crm::Ai::ResponsesClient::Error)
    expect(result.people).to eq([])
  end
end

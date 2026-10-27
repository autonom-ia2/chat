require 'rails_helper'

# #2200: `entry[].changes` traz eventos de teste do painel (field `messages`) e comentários reais (`comments`,
# `mentions`). Antes todo `changes` virava evento de teste.
describe Webhooks::InstagramEventsJob do
  let(:comment_job) { class_double(ApplicationJob, perform_later: true) }
  let(:comment_value) do
    { 'from' => { 'id' => '232323', 'username' => 'cliente' }, 'media' => { 'id' => '123123', 'media_product_type' => 'AD' },
      'id' => '17865799348089039', 'text' => 'quanto custa?' }
  end

  def entry_with(field, value)
    { id: '17841400000000000', time: 1_761_000_000, changes: [{ field: field, value: value }] }.with_indifferent_access
  end

  before do
    stub_const('Webhooks::InstagramCommentJob', comment_job)
    allow(Instagram::TestEventService).to receive(:new).and_call_original
  end

  it 'hands a real comment to the comment job with the account id, the field, the raw value and the time' do
    described_class.perform_now([entry_with('comments', comment_value)])

    expect(comment_job).to have_received(:perform_later).with('17841400000000000', 'comments', comment_value, 1_761_000_000)
    expect(Instagram::TestEventService).not_to have_received(:new)
  end

  it 'hands mentions to the comment job too' do
    described_class.perform_now([entry_with('mentions', { 'comment_id' => '1', 'media_id' => '2' })])

    expect(comment_job).to have_received(:perform_later).with('17841400000000000', 'mentions', { 'comment_id' => '1', 'media_id' => '2' },
                                                              1_761_000_000)
  end

  it 'keeps the dashboard test event (field messages) on the test service' do
    test_service = instance_double(Instagram::TestEventService, perform: true)
    allow(Instagram::TestEventService).to receive(:new).and_return(test_service)
    value = { 'sender' => { 'id' => '12334' }, 'recipient' => { 'id' => '23245' }, 'message' => { 'mid' => 'random_mid', 'text' => 'random_text' } }

    described_class.perform_now([entry_with('messages', value)])

    expect(test_service).to have_received(:perform)
    expect(comment_job).not_to have_received(:perform_later)
  end

  it 'ignores a comment when the consumer job is not deployed yet' do
    hide_const('Webhooks::InstagramCommentJob')

    expect { described_class.perform_now([entry_with('comments', comment_value)]) }.not_to raise_error
  end

  it 'ignores fields without a consumer' do
    described_class.perform_now([entry_with('story_insights', { 'media_id' => '1' })])

    expect(comment_job).not_to have_received(:perform_later)
  end
end

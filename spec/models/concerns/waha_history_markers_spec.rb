require 'rails_helper'

RSpec.describe 'Reserved WAHA history markers', type: :model do
  shared_examples 'an internal marker' do
    let!(:record) do
      previous = Current.waha_history_import
      Current.waha_history_import = true
      create(factory, field => { marker => true })
    ensure
      Current.waha_history_import = previous
    end

    it 'preserves the stored marker when replacing other metadata' do
      record.update!(field => { 'custom' => 'value' })

      expect(record.reload.public_send(field)).to include(marker => true, 'custom' => 'value')
    end

    it 'allows unchanged internal metadata in an ordinary update' do
      record.update!(field => { marker => true, 'custom' => 'value' })

      expect(record.reload.public_send(field)).to include(marker => true, 'custom' => 'value')
    end

    it 'rejects an explicit change using symbol keys before persistence' do
      expect(record.update(field => { marker.to_sym => false })).to be(false)
      expect(record.errors.added?(field, :invalid)).to be(true)
      expect(record.reload.public_send(field)[marker]).to be(true)
    end

    it 'rejects adding a reserved marker to an ordinary record' do
      ordinary = create(factory)

      expect(ordinary.update(field => { marker => true })).to be(false)
      expect(ordinary.errors.added?(field, :invalid)).to be(true)
      expect(ordinary.reload.public_send(field)).not_to have_key(marker)
    end

    [true, false, nil].each do |value|
      it "rejects a new external marker with symbol keys and value #{value.inspect}" do
        ordinary = build(factory, field => { marker.to_sym => value })

        expect(ordinary.valid?).to be(false)
        expect(ordinary.errors.added?(field, :invalid)).to be(true)
        expect(ordinary).not_to be_persisted
      end
    end
  end

  context 'with the serialized message metadata' do
    let(:factory) { :message }
    let(:field) { :content_attributes }
    let(:marker) { 'waha_history_import' }

    it_behaves_like 'an internal marker'
  end

  context 'with the conversation JSONB metadata' do
    let(:factory) { :conversation }
    let(:field) { :additional_attributes }
    let(:marker) { 'waha_history_only' }

    it_behaves_like 'an internal marker'
  end
end

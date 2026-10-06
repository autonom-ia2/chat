require 'rails_helper'

RSpec.describe Waha::FirstConnectionTimestamp do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:started_at) { 1.minute.ago.to_i }
  let(:working_at_ms) { (started_at + 10) * 1000 }
  let(:marker) do
    {
      'status' => 'waiting_connection',
      'started_at' => started_at,
      'before' => 0,
      'chats_offset' => 0,
      'messages_offset' => 0,
      'chat_id' => nil,
      'pass' => 0,
      'imported' => 0,
      'unavailable_media' => 0
    }
  end
  let(:channel) do
    create(
      :channel_api,
      account: account,
      additional_attributes: {
        'provider' => 'waha',
        'session' => '5511999999999',
        'account_token_owner_user_id' => user.id,
        'apps' => [{ 'id' => 'app_chatwoot', 'enabled' => true }],
        'config' => { 'conversations' => { 'syncMessageStatus' => true } },
        'waha_history_import' => marker
      }
    )
  end
  let(:inbox) { channel.inbox }

  it 'grava o primeiro timestamp WORKING e preserva Apps e configuração existentes' do
    described_class.new(
      inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms
    ).perform

    attributes = channel.reload.additional_attributes
    expect(attributes).to include(
      'apps' => [{ 'id' => 'app_chatwoot', 'enabled' => true }],
      'config' => { 'conversations' => { 'syncMessageStatus' => true } }
    )
    expect(attributes.dig('waha_history_import', 'working_at_ms')).to eq(working_at_ms)
    expect(attributes.dig('waha_history_import', 'cutoff_version')).to eq(2)
  end

  it 'preserva o primeiro corte quando uma reconexão chega depois do registro' do
    described_class.new(
      inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms
    ).perform
    channel.update!(additional_attributes: channel.additional_attributes.deep_dup.tap do |attributes|
      attributes['waha_history_import']['status'] = 'running'
    end)

    result = described_class.new(
      inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms + 60_000
    ).perform

    expect(result).to eq(:already_recorded)
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'working_at_ms')).to eq(working_at_ms)
  end

  it 'ignora uma caixa antiga sem marcador sem alterar seus atributos' do
    channel.update!(additional_attributes: channel.additional_attributes.except('waha_history_import'))
    previous_attributes = channel.reload.additional_attributes.deep_dup
    described_class.new(
      inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms
    ).perform
    expect(channel.reload.additional_attributes).to eq(previous_attributes)
  end

  it 'falha fechado para identidade, estado ou timestamp inválidos antes de escrever' do
    channel.update!(additional_attributes: channel.additional_attributes.merge('session' => 'other-session'))
    expect do
      described_class.new(
        inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms
      ).perform
    end.to raise_error(described_class::Error, 'history_connection_invalid')
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'working_at_ms')).to be_nil

    channel.update!(additional_attributes: channel.additional_attributes.merge('session' => '5511999999999'))
    other_user = create(:user, account: account, role: :administrator)
    expect do
      described_class.new(
        inbox: inbox, user: other_user, session: '5511999999999', working_at_ms: working_at_ms
      ).perform
    end.to raise_error(described_class::Error, 'history_connection_invalid')

    expect do
      described_class.new(
        inbox: inbox, user: user, session: '5511999999999', working_at_ms: (started_at * 1000) - 1
      ).perform
    end.to raise_error(described_class::Error, 'history_connection_invalid')
    expect(channel.reload.additional_attributes.dig('waha_history_import', 'working_at_ms')).to be_nil
  end

  it 'não trata um timestamp já existente e malformado como idempotência' do
    channel.update!(
      additional_attributes: channel.additional_attributes.merge(
        'waha_history_import' => marker.merge('working_at_ms' => 'not-an-integer', 'cutoff_version' => 2)
      )
    )

    expect do
      described_class.new(
        inbox: inbox, user: user, session: '5511999999999', working_at_ms: working_at_ms
      ).perform
    end.to raise_error(described_class::Error, 'history_connection_invalid')
  end
end

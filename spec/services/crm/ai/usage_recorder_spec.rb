require 'rails_helper'

RSpec.describe Crm::Ai::UsageRecorder do
  describe '.record' do
    it 'persists one usage event with metadata only' do
      account, = create_account_and_user

      expect do
        described_class.record(
          account: account,
          feature: 'agente_resposta',
          model: 'gpt-5.4-mini',
          usage: { 'input_tokens' => 1200, 'output_tokens' => 300, 'input_tokens_details' => { 'cached_tokens' => 200 } },
          reasoning_effort: 'low',
          latency_ms: 850
        )
      end.to change(Crm::AiUsageEvent, :count).by(1)

      event = Crm::AiUsageEvent.last
      expect(event).to have_attributes(
        account_id: account.id,
        feature: 'agente_resposta',
        model: 'gpt-5.4-mini',
        reasoning_effort: 'low',
        input_tokens: 1200,
        cached_tokens: 200,
        output_tokens: 300,
        latency_ms: 850
      )
    end

    it 'persists cache write tokens reported by the 5.6 API and prices them at their own rate' do
      account, = create_account_and_user

      described_class.record(
        account: account,
        feature: 'agente_resposta',
        model: 'gpt-5.6-luna',
        usage: {
          'input_tokens' => 4176,
          'output_tokens' => 5,
          'input_tokens_details' => { 'cached_tokens' => 0, 'cache_write_tokens' => 4173 }
        }
      )

      event = Crm::AiUsageEvent.last
      expect(event).to have_attributes(input_tokens: 4176, cached_tokens: 0, cache_write_tokens: 4173, output_tokens: 5)
      # (3*1.0 + 4173*1.25 + 5*6.0) / 1_000_000
      expect(event.cost_estimate.to_f).to be_within(1e-6).of(0.00524925)
    end

    it 'defaults cache write tokens to zero when the model does not report them' do
      account, = create_account_and_user

      described_class.record(
        account: account,
        feature: 'copilot',
        model: 'gpt-5.4-mini',
        usage: { 'input_tokens' => 100, 'output_tokens' => 10, 'input_tokens_details' => { 'cached_tokens' => 0 } }
      )

      expect(Crm::AiUsageEvent.last.cache_write_tokens).to eq(0)
    end

    it 'records the estimated cost from the price table when an ENV rate is set' do
      account, = create_account_and_user

      ClimateControl.modify(CRM_AI_PRICE_GPT_5_4_MINI: '0.15,0.015,0.6') do
        described_class.record(
          account: account,
          feature: 'copilot',
          model: 'gpt-5.4-mini',
          usage: { 'input_tokens' => 1000, 'output_tokens' => 500, 'input_tokens_details' => { 'cached_tokens' => 0 } }
        )
      end

      # (1000*0.15 + 500*0.6) / 1_000_000 = 450 / 1_000_000
      expect(Crm::AiUsageEvent.last.cost_estimate).to be_within(1e-9).of(0.00045)
    end

    it 'stores the pipeline id when a pipeline is given' do
      account, user = create_account_and_user
      pipeline, = create_crm_pipeline(account: account, user: user)

      described_class.record(
        account: account, feature: 'kb_revisao', model: 'gpt-5.4-mini',
        usage: {}, pipeline: pipeline
      )

      expect(Crm::AiUsageEvent.last.pipeline_id).to eq(pipeline.id)
    end

    it 'is a no-op when account is blank' do
      expect do
        described_class.record(account: nil, feature: 'agente_resposta', model: 'gpt-5.4-mini', usage: {})
      end.not_to change(Crm::AiUsageEvent, :count)
    end

    it 'is a no-op when feature is blank' do
      account, = create_account_and_user
      expect do
        described_class.record(account: account, feature: '', model: 'gpt-5.4-mini', usage: {})
      end.not_to change(Crm::AiUsageEvent, :count)
    end

    it 'never raises when persistence fails (best-effort telemetry)' do
      account, = create_account_and_user
      allow(Crm::AiUsageEvent).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'boom')

      result = nil
      expect do
        result = described_class.record(account: account, feature: 'agente_resposta', model: 'gpt-5.4-mini', usage: {})
      end.not_to raise_error
      expect(result).to be_nil
    end
  end

  describe '.extract_tokens' do
    it 'reads the Responses API shape (input/output + cached details)' do
      tokens = described_class.extract_tokens(
        'input_tokens' => 100, 'output_tokens' => 40, 'input_tokens_details' => { 'cached_tokens' => 25 }
      )
      expect(tokens).to eq(input: 100, output: 40, cached: 25, cache_write: 0)
    end

    it 'reads the chat completions shape (prompt/completion + prompt details)' do
      tokens = described_class.extract_tokens(
        prompt_tokens: 80, completion_tokens: 20, prompt_tokens_details: { cached_tokens: 10 }
      )
      expect(tokens).to eq(input: 80, output: 20, cached: 10, cache_write: 0)
    end

    it 'defaults every counter to zero for an empty usage payload' do
      expect(described_class.extract_tokens(nil)).to eq(input: 0, output: 0, cached: 0, cache_write: 0)
    end

    it 'reads cache write tokens from the 5.6 details payload' do
      tokens = described_class.extract_tokens(
        'input_tokens' => 4176, 'output_tokens' => 5,
        'input_tokens_details' => { 'cached_tokens' => 0, 'cache_write_tokens' => 4173 }
      )
      expect(tokens).to eq(input: 4176, output: 5, cached: 0, cache_write: 4173)
    end
  end
end

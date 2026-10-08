require 'rails_helper'

# Funil que não conta como venda (#1144): o desfecho grava resolved/cancelled, nunca won/lost, e por isso
# fica fora de toda métrica de venda e de todo envio de conversão.
RSpec.describe Crm::Cards::Outcome do
  let!(:account_and_user) { create_account_and_user }
  let(:account) { account_and_user.first }
  let(:user) { account_and_user.last }
  let(:sale_pipeline) { create_crm_pipeline(account: account, user: user, name: 'Comercial') }
  let(:service_pipeline) do
    pipeline, stage = create_crm_pipeline(account: account, user: user, name: 'Sinistro')
    pipeline.update!(counts_as_sale: false)
    [pipeline, stage]
  end

  def card_in(pipeline_and_stage, **attrs)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Card', **attrs)
  end

  def close(card, result)
    Crm::Cards::Closer.new(card: card, actor: user, result: result, value_cents: 5000, lost_reason: 'Sem retorno').perform
  end

  describe '.status_for' do
    it 'translates the verb to the funnel kind and keeps the rest' do
      sale, = sale_pipeline
      service, = service_pipeline

      expect(described_class.status_for(sale, 'resolved')).to eq('won')
      expect(described_class.status_for(service, :won)).to eq('resolved')
      expect(described_class.status_for(service, 'lost')).to eq('cancelled')
      expect(described_class.status_for(service, 'open')).to eq('open')
    end
  end

  describe 'closing a card' do
    it 'keeps won/lost in a sale funnel' do
      card = close(card_in(sale_pipeline), 'won')

      expect(card.reload).to be_won
      expect(card.value_cents).to eq(5000)
      expect(account.crm_activities.where(card: card).last.event_type).to eq('won')
    end

    it 'writes resolved and cancelled in a non-sale funnel, with closed_at and a matching activity' do
      resolved = close(card_in(service_pipeline), 'won')
      cancelled = close(card_in(service_pipeline), 'lost')

      expect(resolved.reload).to be_resolved
      expect(resolved.closed_at).to be_present
      expect(resolved.value_cents).not_to eq(5000)
      expect(cancelled.reload).to be_cancelled
      expect(cancelled.lost_reason).to eq('Sem retorno')
      expect(account.crm_activities.where(card: resolved).last.event_type).to eq('resolved')
      expect(account.crm_activities.where(card: cancelled).last.event_type).to eq('cancelled')
    end

    it 'reopens a cancelled card' do
      card = close(card_in(service_pipeline), 'cancelled')
      close(card, 'open')

      expect(card.reload).to be_open
      expect(card.closed_at).to be_nil
    end

    it 'creates a card already closed with the funnel outcome' do
      pipeline, stage = service_pipeline
      card = Crm::Cards::Creator.new(account: account, user: user,
                                     params: { pipeline_id: pipeline.id, stage_id: stage.id, title: 'Já pago', status: 'won' })
                                .perform

      expect(card).to be_resolved
    end
  end

  describe 'moving a closed card to a funnel of the other kind' do
    it 'carries the equivalent outcome and keeps the original close date' do
      card = close(card_in(sale_pipeline), 'won')
      closed_at = card.reload.closed_at
      service, = service_pipeline
      target = create_crm_stage(account: account, pipeline: service, name: 'Outra', position: 2)

      travel 1.hour do
        Crm::Cards::Mover.new(card: card, actor: user, target_stage: target, automation_context: { skip_automations: true }).perform
      end

      expect(card.reload).to be_resolved
      expect(card.pipeline).to eq(service)
      expect(card.closed_at).to be_within(1.second).of(closed_at)
    end

    it 'still resets the close date when the outcome itself changes' do
      card = close(card_in(sale_pipeline), 'won')

      travel 1.hour do
        close(card, 'lost')
      end

      expect(card.reload.closed_at).to be > 30.minutes.from_now
    end
  end

  describe 'model guard' do
    it 'refuses a sale result in a non-sale funnel and the other way round' do
      expect { card_in(service_pipeline).update!(status: :won) }.to raise_error(ActiveRecord::RecordInvalid)
      expect { card_in(sale_pipeline).update!(status: :resolved) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'keeps an old won card editable after its funnel stops counting as a sale' do
      card = close(card_in(sale_pipeline), 'won')
      card.pipeline.update!(counts_as_sale: false)

      expect { card.reload.update!(title: 'Renomeado') }.not_to raise_error
      expect(card).to be_won
    end
  end

  describe 'conversion sync' do
    it 'turns Meta and Google off when the funnel stops counting as a sale' do
      pipeline, = sale_pipeline
      pipeline.update!(metadata: { 'meta_sync' => { 'enabled' => true, 'events' => { 'won' => true } },
                                   'google_sync' => { 'enabled' => true } })

      pipeline.update!(counts_as_sale: false)

      expect(pipeline.reload.metadata.dig('meta_sync', 'enabled')).to be(false)
      expect(pipeline.metadata.dig('meta_sync', 'events', 'won')).to be(true)
      expect(pipeline.metadata.dig('google_sync', 'enabled')).to be(false)
    end
  end

  describe 'automation' do
    it 'does not close again a card already resolved by "mark as won"' do
      card = close(card_in(service_pipeline), 'won')
      host = Class.new do
        include AutomationRules::CrmActions

        def initialize(card) = @card = card
        def crm_card = @card
      end.new(card)
      allow(Crm::Cards::Closer).to receive(:new).and_call_original

      host.send(:crm_mark_card_won, nil)

      expect(Crm::Cards::Closer).not_to have_received(:new)
    end
  end
end

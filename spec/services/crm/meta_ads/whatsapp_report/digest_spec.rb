require 'rails_helper'

# Números do resumo diário e regra do alerta (#1100, F4b): ontem e hoje no fuso da conta de anúncios, do banco. O
# que fazer hoje vem do consultor (F5, #1110).
RSpec.describe Crm::MetaAds::WhatsappReport::Digest do
  let(:account) { create(:account) }
  let(:connection) { create_meta_ads_insights_connection(account) }
  let(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account)).first }
  let(:quote_stage) do
    account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Proposta', position: 1, metadata: { 'funnel_stage_type' => 'opportunity' })
  end
  let(:promo) { '120254710362980416' }
  let(:capa) { '120254710382780416' }
  # 07/10 às 8h de Brasília: ontem é 06/10.
  let(:now) { Time.zone.parse('2026-10-07T08:00:00-03:00') }

  def spend(ad_id, date, value)
    Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: date, currency: 'BRL',
                                    spend: value, attribution_window: '7d_click', fetched_at: now)
  end

  def from_ad(ad_id, at:, card: nil)
    conversation = create(:conversation, account: account)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: SecureRandom.hex(4), origin: 'whatsapp',
                            certainty: 'ad', ad_id: ad_id, touched_at: at)
    Crm::Card.create!(account: account, pipeline: pipeline, title: 'Cotação', currency: 'BRL', primary_conversation: conversation, **card) if card
  end

  describe 'resumo de ontem' do
    # O consultor (Advisor::Analysis) é do construtor A: aqui ele é stub (a integração roda sem stub).
    let(:advice) do
      { run_id: 812, local_date: '2026-10-07', rules_version: 'f5.1', writer: { status: 'written', reason: nil },
        actions: [{ id: 4521, position: 1, kind: 'stalled_quotes', variant: nil, status: 'open', source: 'ai',
                    headline: 'Retome as 2 propostas.', body: 'Comece hoje.', facts: { count: 2, value: 1500.0, days: 3 } },
                  { id: 4522, position: 2, kind: 'slow_response', variant: nil, status: 'open', source: 'rule', facts: {} }] }
    end
    # rubocop:disable RSpec/VerifiedDoubleReference
    let!(:analysis) { class_double('Crm::MetaAds::Advisor::Analysis', current: advice, daily: advice, mark_shown!: nil).as_stubbed_const }
    # rubocop:enable RSpec/VerifiedDoubleReference

    it 'soma gasto, conversas, propostas e vendas de ontem e aponta o anúncio que mais trouxe conversa' do
      travel_to(now) do
        Crm::MetaAdObject.create!(account: account, meta_object_id: promo, object_type: 'ad', name: 'Promo outubro', fetched_at: now)
        spend(promo, Date.new(2026, 10, 6), 100)
        spend(capa, Date.new(2026, 10, 6), 20)
        spend(promo, Date.new(2026, 10, 5), 999) # anteontem
        from_ad(promo, at: Time.zone.parse('2026-10-06T00:30:00-03:00'), card: { stage: quote_stage, status: :won, value_cents: 90_000 })
        from_ad(promo, at: Time.zone.parse('2026-10-06T22:00:00-03:00'), card: { stage: quote_stage })
        from_ad(capa, at: Time.zone.parse('2026-10-06T12:00:00-03:00'))
        from_ad(capa, at: Time.zone.parse('2026-10-05T23:59:00-03:00')) # anteontem em Brasília

        payload = described_class.new(connection).payload

        expect(payload).to include(date: Date.new(2026, 10, 6), currency: 'BRL', spend: 120.0, conversations: 3, cost_per_conversation: 40.0,
                                   quotes: 2, sales: 1, sales_value: 900.0)
        expect(payload[:best_ad]).to eq(ad_id: promo, name: 'Promo outubro', conversations: 2)
        expect(payload).not_to have_key(:ai_action)
      end
    end

    describe 'o que fazer hoje: a primeira ação do consultor (F5)' do
      it 'o envio das 8h pede a análise do dia, que pode escrever pela IA, no idioma do resumo' do
        travel_to(now) do
          account.update!(locale: 'pt_BR')
          spend(promo, Date.new(2026, 10, 6), 10)

          expect(described_class.new(connection, with_ai: true).payload[:action]).to eq(advice[:actions].first)
          expect(analysis).to have_received(:daily).with(connection, language: 'pt_BR')
          expect(analysis).not_to have_received(:current)
        end
      end

      it 'o envio de teste não chama a IA: só a análise atual, como resumo' do
        travel_to(now) do
          account.update!(locale: 'en')
          spend(promo, Date.new(2026, 10, 6), 10)

          expect(described_class.new(connection).payload[:action]).to eq(advice[:actions].first)
          expect(analysis).to have_received(:current).with(connection, locale: 'en', trigger: 'digest')
          expect(analysis).not_to have_received(:daily)
        end
      end

      it 'marca como mostrada só a ação 1, a que o WhatsApp mostra; o filler não tem linha' do
        travel_to(now) do
          spend(promo, Date.new(2026, 10, 6), 10)
          described_class.new(connection, with_ai: true).mark_shown!

          expect(analysis).to have_received(:mark_shown!).once.with([4521])

          advice[:actions] = [{ id: nil, position: 1, kind: 'on_track', status: nil, source: 'rule', facts: {} }]
          described_class.new(connection, with_ai: true).mark_shown!

          expect(analysis).to have_received(:mark_shown!).once
        end
      end
    end

    it 'ontem sem gasto e sem conversa não tem o que contar, e não chama o consultor' do
      travel_to(now) do
        spend(promo, Date.new(2026, 10, 7), 50) # hoje

        digest = described_class.new(connection, with_ai: true)

        expect(digest).to be_nothing_to_report
        expect(analysis).not_to have_received(:daily)
        expect(digest.payload).to include(spend: 0.0, conversations: 0, cost_per_conversation: nil, best_ad: nil)
      end
    end
  end

  describe Crm::MetaAds::WhatsappReport::SpendAlert do
    # 16h30 de Brasília.
    let(:afternoon) { Time.zone.parse('2026-10-07T16:30:00-03:00') }

    it 'sem custo por conversa nos 30 dias, entra o anúncio que gastou o piso hoje sem conversa' do
      travel_to(afternoon) do
        spend(promo, Date.new(2026, 10, 7), 29.99)
        spend(capa, Date.new(2026, 10, 7), 30)

        expect(described_class.new(connection).candidate).to eq(ad_id: capa, name: capa, spend: 30.0, currency: 'BRL', threshold: 30)
      end
    end

    it 'com custo por conversa, o corte é 2 vezes ele; anúncio com conversa hoje fica fora; vai o de maior gasto' do
      travel_to(afternoon) do
        # 30 dias: R$ 96 e 11 conversas → R$ 8,73 por conversa → corte R$ 17,46.
        spend(promo, Date.new(2026, 10, 1), 50)
        10.times { from_ad(promo, at: Time.zone.parse('2026-10-01T10:00:00-03:00')) }
        spend(promo, Date.new(2026, 10, 7), 25)
        spend(capa, Date.new(2026, 10, 7), 21)
        spend('120254710000000001', Date.new(2026, 10, 7), 0) # abaixo do corte
        from_ad(promo, at: Time.zone.parse('2026-10-07T09:00:00-03:00'))

        candidate = described_class.new(connection).candidate

        expect(candidate).to include(ad_id: capa, spend: 21.0, threshold: 17.46)
      end
    end

    it 'nenhum anúncio no critério: sem alerta' do
      travel_to(afternoon) do
        spend(promo, Date.new(2026, 10, 7), 10)

        expect(described_class.new(connection).candidate).to be_nil
      end
    end
  end
end

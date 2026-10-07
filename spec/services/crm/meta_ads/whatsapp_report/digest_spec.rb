require 'rails_helper'

# Números do resumo diário e regra do alerta (#1100, F4b): ontem e hoje no fuso da conta de anúncios, do banco.
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
        expect(payload[:action]).to eq(kind: 'wait', ad_name: 'Promo outubro', missing_conversations: 18)
      end
    end

    describe 'o que fazer hoje' do
      let(:zone) { ActiveSupport::TimeZone['America/Sao_Paulo'] }

      def panel_cache
        report = Crm::MetaAds::Panel::Report.new(connection, days: 30).payload
        Crm::MetaAds::Panel::AiActionCache.new(connection: connection, report: report, zone: zone, locale: 'pt_BR')
      end

      after do
        Redis::Alfred.scan_each(match: "#{Crm::MetaAds::Panel::AiActionCache::PREFIX}:#{account.id}:*").each { |key| Redis::Alfred.delete(key) }
      end

      it 'o envio das 8h usa o texto da IA guardado pelo painel no dia, sem chamada nova' do
        travel_to(now) do
          account.update!(locale: 'pt_BR')
          spend(promo, Date.new(2026, 10, 6), 10)
          panel_cache.write(source: 'ai', kind: 'on_track', headline: 'Siga com o Promo outubro.')
          expect(Crm::Ai::ResponsesClient).not_to receive(:new)

          payload = described_class.new(connection, with_ai: true).payload

          expect(payload[:ai_action]).to include(source: 'ai', headline: 'Siga com o Promo outubro.')
          expect(payload[:action]).to eq(Crm::MetaAds::Panel::Report.new(connection, days: 30).payload[:action])
        end
      end

      it 'sem texto guardado, o envio das 8h pede à IA no idioma da conta, no período de 30 dias do painel' do
        travel_to(now) do
          account.update!(locale: 'pt_BR')
          spend(promo, Date.new(2026, 10, 6), 10)
          answer = { source: 'ai', kind: 'wait', headline: 'Deixe rodar.', body: nil }
          allow(Crm::MetaAds::Panel::AiAction).to receive(:daily).and_return(answer)

          expect(described_class.new(connection, with_ai: true).payload[:ai_action]).to eq(answer)
          expect(Crm::MetaAds::Panel::AiAction).to have_received(:daily).with(connection: connection, days: 30, language: 'pt_BR')
        end
      end

      it 'IA indisponível ou com falha: fica só a regra' do
        travel_to(now) do
          spend(promo, Date.new(2026, 10, 6), 10)
          allow(Crm::MetaAds::Panel::AiAction).to receive(:daily).and_return(source: 'rule', reason: 'ai_error', kind: 'wait')

          payload = described_class.new(connection, with_ai: true).payload

          expect(payload[:ai_action]).to be_nil
          expect(payload[:action][:kind]).to eq('wait')
        end
      end

      it 'o envio de teste não chama a IA' do
        travel_to(now) do
          spend(promo, Date.new(2026, 10, 6), 10)
          expect(Crm::MetaAds::Panel::AiAction).not_to receive(:daily)

          expect(described_class.new(connection).payload[:ai_action]).to be_nil
        end
      end
    end

    it 'ontem sem gasto e sem conversa não tem o que contar' do
      travel_to(now) do
        spend(promo, Date.new(2026, 10, 7), 50) # hoje

        digest = described_class.new(connection)

        expect(digest).to be_nothing_to_report
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

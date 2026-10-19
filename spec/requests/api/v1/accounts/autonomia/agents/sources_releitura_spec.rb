require 'rails_helper'

# #1426 (revisão adversarial) — a releitura não para o OCR da leitura em curso. Na Fase 2, ler de novo um material que
# ainda está sendo lido é recusado (422, texto leigo); parado além do teto da releitura (o worker caiu) pode. Fora da
# Fase 2, como antes.
RSpec.describe 'Autonomia sources - releitura', type: :request do
  let(:account) { create(:account, internal_attributes: { 'autonomia_agents_enabled' => true }) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Bia', agent_type: 'support', mode: :guided,
                                     status: :draft, enabled: false, actuation: :external)
  end
  let(:material) { agent.sources.create!(account: account, source_type: 'txt', reference: 'cardapio.txt', status: :ready) }

  around do |example|
    with_modified_env AUTONOMIA_AGENTS_ENABLED: 'true' do
      example.run
    end
  end

  def reler
    post "/api/v1/accounts/#{account.id}/autonomia/agents/#{agent.id}/sources/#{material.id}/resync",
         headers: administrator.create_new_auth_token
  end

  def lendo_desde(momento)
    material.begin_ingestion!
    material.update_columns(updated_at: momento) # rubocop:disable Rails/SkipsModelValidations
  end

  context 'with the Fase 2' do
    before { Autonomia::Agents::Fase2.ligar!(account) }

    it 'refuses to read again a material that is still being read' do
      lendo_desde(1.minute.ago)

      expect { reler }.not_to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body['error']).to eq(I18n.t('autonomia.source.lendo_ainda'))
    end

    it 'reads again a material stopped beyond the ceiling of the reading' do
      lendo_desde((Autonomia::Agents::Source::TETO_DA_RELEITURA + 1.minute).ago)

      expect { reler }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
      expect(response).to have_http_status(:accepted)
    end

    # S3 — a Lia fica como na main: relê a qualquer momento.
    it 'reads again a material of the Lia that is still being read' do
      lia = Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'insurance_quote', status: :draft)
      da_lia = lia.sources.create!(account: account, source_type: 'txt', reference: 'tabela.txt', status: :ready)
      da_lia.begin_ingestion!

      expect do
        post "/api/v1/accounts/#{account.id}/autonomia/agents/#{lia.id}/sources/#{da_lia.id}/resync",
             headers: administrator.create_new_auth_token
      end.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
      expect(response).to have_http_status(:accepted)
    end

    it 'reads again a material that is not being read' do
      expect { reler }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
      expect(response).to have_http_status(:accepted)
    end
  end

  it 'reads again a material being read outside the Fase 2, as before' do
    lendo_desde(1.minute.ago)

    expect { reler }.to have_enqueued_job(Autonomia::Agents::Knowledge::IngestJob)
    expect(response).to have_http_status(:accepted)
  end
end

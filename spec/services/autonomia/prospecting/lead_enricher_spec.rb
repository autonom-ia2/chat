require 'rails_helper'

# Caracterização do enriquecimento (#683). Os casos DIVERGE que a E0 corrigiu foram
# invertidos: interruptor no superadmin e IA só na credencial do Kanban da conta.
RSpec.describe Autonomia::Prospecting::LeadEnricher do
  let(:account) { create(:account) }
  let(:user) { create(:user, :administrator, account: account) }
  let(:setting) { Autonomia::Prospecting::Setting.for_account(account) }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account,
      provider: 'mock',
      provider_place_id: 'places/sorriso',
      name: 'Clinica Sorriso',
      website: 'https://clinicasorriso.example.com',
      phone: '+5541999990000'
    )
  end
  let(:scraped) do
    {
      'website' => 'https://clinicasorriso.example.com',
      'title' => 'Clinica Sorriso',
      'description' => 'Odontologia em Curitiba',
      'email' => 'contato@clinicasorriso.example.com',
      'whatsapp' => '+5541999990000',
      'instagram' => 'https://instagram.com/clinicasorriso',
      'linkedin' => 'https://linkedin.com/company/clinicasorriso',
      'cnpj' => '12.345.678/0001-90'
    }
  end
  let(:scraper) { instance_double(Autonomia::Prospecting::WebsiteScraper) }
  let(:ai_client) { instance_double(Crm::Ai::ResponsesClient) }
  let(:ai_payload) do
    {
      'decision_name' => 'Ana Souza',
      'decision_role' => 'Sócia',
      'decision_confidence' => 0.8,
      'decision_source_url' => 'https://clinicasorriso.example.com/equipe',
      'decision_linkedin' => nil,
      'decision_instagram' => nil,
      'summary' => 'Clínica odontológica com duas unidades.',
      'signals' => ['site ativo']
    }
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    Autonomia::Prospecting::Config.enable_research_for!(account)
    InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').destroy_all
    allow(Integrations::Openai::KeyValidator).to receive(:valid?).and_return(true)
    allow(Autonomia::Prospecting::WebsiteScraper).to receive(:new).and_return(scraper)
    allow(scraper).to receive(:perform).and_return(Autonomia::Prospecting::WebsiteScraper::Result.new(data: scraped))
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(ai_client)
    allow(ai_client).to receive(:create).and_return({ text: ai_payload.to_json })
  end

  def enrich
    described_class.new(lead: lead, user: user).perform
  end

  def create_kanban_hook(settings)
    create(:integrations_hook, account: account, app_id: 'crm_kanban_ai', hook_type: :account, settings: settings)
  end

  describe 'interruptor' do
    it 'recusa com a pesquisa desligada pelo superadmin e marca o lead como falho' do
      Autonomia::Prospecting::Config.disable_research_for!(account)

      expect { enrich }.to raise_error(described_class::Error, 'prospecting.enrichment.disabled')
      expect(lead.reload).to be_enrichment_failed
      expect(lead.enrichment_error).to eq('prospecting.enrichment.disabled')
      expect(Autonomia::Prospecting::WebsiteScraper).not_to have_received(:new)
    end

    it 'recusa com o módulo de prospecção desligado na conta, mesmo com a pesquisa ligada' do
      Autonomia::Prospecting::Config.disable_for!(account)

      expect { enrich }.to raise_error(described_class::Error, 'prospecting.enrichment.disabled')
      expect(Autonomia::Prospecting::WebsiteScraper).not_to have_received(:new)
    end

    it 'ignora enrichment_enabled da conta: ligado não libera sem a pesquisa, desligado não trava com ela' do
      setting.update!(enrichment_enabled: true)
      Autonomia::Prospecting::Config.disable_research_for!(account)
      expect { enrich }.to raise_error(described_class::Error, 'prospecting.enrichment.disabled')

      setting.update!(enrichment_enabled: false)
      Autonomia::Prospecting::Config.enable_research_for!(account)
      expect(enrich).to be_enrichment_completed
    end
  end

  describe 'credencial de IA' do
    it 'não chama a IA sem hook crm_kanban_ai, mesmo existindo a chave do sistema' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-do-sistema')

      result = enrich

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(result).to be_enrichment_completed
      expect(result.enrichment_source).to eq('site')
    end

    it 'usa a chave do hook crm_kanban_ai da conta quando ele existe' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-do-sistema')
      create_kanban_hook({ 'api_key' => 'chave-da-conta' })

      enrich

      expect(Crm::Ai::ResponsesClient).to have_received(:new)
        .with(hash_including(credential: hash_including(api_key: 'chave-da-conta', source: :hook),
                             feature: 'prospecting_lead_enrichment'))
    end

    it 'não cai para a chave do sistema quando o hook existe com a IA desligada' do
      InstallationConfig.create!(name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'chave-do-sistema')
      create_kanban_hook({ 'api_key' => 'chave-da-conta', 'enabled' => false })

      result = enrich

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(result).to be_enrichment_completed
      expect(result.enrichment_source).to eq('site')
    end

    it 'conclui só com o site quando não há credencial nenhuma' do
      result = enrich

      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      expect(result).to be_enrichment_completed
      expect(result.enrichment_source).to eq('site')
      expect(result.enrichment_summary).to eq('Clinica Sorriso - Odontologia em Curitiba')
      expect(result.enriched_data['ai']).to eq({})
    end
  end

  describe 'resultado' do
    before { create_kanban_hook({ 'api_key' => 'chave-da-conta' }) }

    it 'marca completed com a fonte site_and_autonomia_ai e grava o que o site trouxe' do
      result = enrich

      expect(result).to be_enrichment_completed
      expect(result.enrichment_completed_at).to be_present
      expect(result.enrichment_error).to be_nil
      expect(result.enrichment_source).to eq('site_and_autonomia_ai')
      expect(result.enriched_email).to eq('contato@clinicasorriso.example.com')
      expect(result.enriched_cnpj).to eq('12.345.678/0001-90')
    end

    it 'grava decisor confiante e resumo da IA' do
      result = enrich

      expect(result.decision_name).to eq('Ana Souza')
      expect(result.decision_role).to eq('Sócia')
      expect(result.decision_source_url).to eq('https://clinicasorriso.example.com/equipe')
      expect(result.decision_linkedin).to eq('https://linkedin.com/company/clinicasorriso')
      expect(result.enrichment_summary).to eq('Clínica odontológica com duas unidades.')
    end

    it 'descarta nome e cargo do decisor com confiança abaixo de 0.6, mas guarda a confiança' do
      allow(ai_client).to receive(:create).and_return({ text: ai_payload.merge('decision_confidence' => 0.5).to_json })

      result = enrich

      expect(result.decision_name).to be_nil
      expect(result.decision_role).to be_nil
      expect(result.decision_source_url).to be_nil
      expect(result.decision_confidence.to_f).to eq(0.5)
    end

    it 'engole erro da IA e conclui só com o site' do
      allow(ai_client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'timeout')

      result = enrich

      expect(result).to be_enrichment_completed
      expect(result.enrichment_source).to eq('site')
    end

    it 'engole JSON inválido da IA e conclui só com o site' do
      allow(ai_client).to receive(:create).and_return({ text: 'não é json' })

      expect(enrich.enrichment_source).to eq('site')
    end

    it 'não raspa site quando o lead não tem website' do
      lead.update!(website: nil)

      result = enrich

      expect(Autonomia::Prospecting::WebsiteScraper).not_to have_received(:new)
      expect(result.enriched_data.keys).to eq(['ai'])
      expect(result.enrichment_source).to eq('site_and_autonomia_ai')
    end

    it 'marca failed com a mensagem e levanta Error quando algo inesperado quebra' do
      allow(scraper).to receive(:perform).and_raise(RuntimeError, 'quebrou no meio')

      expect { enrich }.to raise_error(described_class::Error, 'quebrou no meio')
      expect(lead.reload).to be_enrichment_failed
      expect(lead.enrichment_error).to eq('quebrou no meio')
      expect(lead.enrichment_completed_at).to be_present
    end
  end
end

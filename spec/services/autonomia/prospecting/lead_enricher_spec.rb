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

    # Com a pesquisa de empresa e decisor (#679), quem decide é o quadro de sócios: o enriquecimento fica com site,
    # e-mail, WhatsApp, redes e CNPJ do site, e o resumo da IA. O decisor da IA não é gravado, nem vira confiança sem
    # nome, e a rede da empresa nunca cai no decisor.
    it 'grava o resumo da IA e não grava decisor, confiança nem rede no decisor' do
      result = enrich

      expect(result).to have_attributes(
        decision_name: nil, decision_role: nil, decision_confidence: nil, decision_source_url: nil,
        decision_linkedin: nil, decision_instagram: nil,
        enriched_linkedin: 'https://linkedin.com/company/clinicasorriso',
        enrichment_summary: 'Clínica odontológica com duas unidades.'
      )
      expect(result.enriched_data['ai'].keys).to contain_exactly('summary', 'signals')
    end

    it 'decisor confiante da IA sozinho não conta como enriquecimento útil' do
      lead.update!(website: nil)
      allow(ai_client).to receive(:create).and_return({ text: ai_payload.merge('summary' => nil, 'signals' => []).to_json })

      result = enrich

      expect(result).to be_enrichment_failed
      expect(result.enrichment_error).to eq('empty_result')
    end

    # O gabarito compara o método novo com o de hoje: o decisor da IA continua acessível, sem gravar nada.
    it '.ai_decision devolve o decisor da IA sem gravar no lead' do
      decision = described_class.ai_decision(lead)

      expect(decision).to eq(
        'decision_name' => 'Ana Souza', 'decision_role' => 'Sócia', 'decision_confidence' => 0.8,
        'decision_source_url' => 'https://clinicasorriso.example.com/equipe', 'decision_linkedin' => nil,
        'decision_instagram' => nil, 'confident' => true
      )
      expect(lead.reload).to have_attributes(decision_name: nil, enrichment_status: 'pending')
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

    it 'marca failed com a mensagem, conta a tentativa e levanta Error quando algo inesperado quebra' do
      allow(scraper).to receive(:perform).and_raise(RuntimeError, 'quebrou no meio')

      expect { enrich }.to raise_error(described_class::Error, 'quebrou no meio')
      expect(lead.reload).to be_enrichment_failed
      expect(lead.enrichment_error).to eq('quebrou no meio')
      expect(lead.enrichment_completed_at).to be_present
      expect(lead.enrichment_failed_attempts).to eq(1)
    end

    it 'aceita a assinatura sem usuário, como o job chama' do
      expect(described_class.new(lead: lead).perform).to be_enrichment_completed
    end
  end

  # Falha honesta (#678 frente D): site fora do ar, bloqueado ou vazio não vira "enriquecido" vazio.
  describe 'falha honesta' do
    let(:previous_data) do
      {
        enrichment_status: 'completed',
        enriched_data: { 'title' => 'Clinica Antiga', 'ai' => { 'summary' => 'Resumo antigo' } },
        enriched_email: 'antigo@clinicasorriso.example.com',
        enriched_whatsapp: '+5541911112222',
        enriched_instagram: 'https://instagram.com/antiga',
        enriched_facebook: 'https://facebook.com/antiga',
        enriched_linkedin: 'https://linkedin.com/company/antiga',
        enriched_cnpj: '11.111.111/0001-11',
        decision_name: 'Bruno Lima',
        decision_role: 'Diretor',
        decision_confidence: 0.9,
        decision_source_url: 'https://clinicasorriso.example.com/sobre',
        enrichment_summary: 'Resumo antigo'
      }
    end

    before { create_kanban_hook({ 'api_key' => 'chave-da-conta' }) }

    def scrape_returns(data)
      allow(scraper).to receive(:perform).and_return(Autonomia::Prospecting::WebsiteScraper::Result.new(data: data))
    end

    %w[timeout blocked_url empty_page http_503].each do |code|
      it "marca failed com o código #{code}, conta a tentativa e não chama a IA" do
        scrape_returns('error' => code, 'scraped_at' => Time.current.iso8601)

        result = enrich

        expect(result).to be_enrichment_failed
        expect(result.enrichment_error).to eq(code)
        expect(result.enrichment_failed_attempts).to eq(1)
        expect(result.enrichment_completed_at).to be_present
        expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
      end
    end

    it 'soma as tentativas que falharam e zera quando uma dá certo' do
      scrape_returns('error' => 'timeout')

      enrich
      expect(enrich.enrichment_failed_attempts).to eq(2)

      scrape_returns(scraped)
      result = enrich

      expect(result).to be_enrichment_completed
      expect(result.enrichment_failed_attempts).to eq(0)
      expect(result.enrichment_error).to be_nil
    end

    it 'falha sem apagar o que um enriquecimento anterior achou' do
      lead.update!(previous_data)
      scrape_returns('error' => 'timeout')

      result = enrich

      expect(result).to be_enrichment_failed
      expect(result).to have_attributes(
        enriched_email: 'antigo@clinicasorriso.example.com',
        enriched_whatsapp: '+5541911112222',
        enriched_instagram: 'https://instagram.com/antiga',
        enriched_facebook: 'https://facebook.com/antiga',
        enriched_linkedin: 'https://linkedin.com/company/antiga',
        enriched_cnpj: '11.111.111/0001-11',
        decision_name: 'Bruno Lima',
        enrichment_summary: 'Resumo antigo'
      )
      expect(result.enriched_data).to include('title' => 'Clinica Antiga')
    end

    it 'marca failed com empty_result quando nem o site nem a IA trazem nada' do
      lead.update!(website: nil)
      allow(ai_client).to receive(:create).and_return(
        { text: ai_payload.merge('decision_name' => nil, 'decision_confidence' => 0, 'summary' => nil, 'signals' => []).to_json }
      )

      result = enrich

      expect(result).to be_enrichment_failed
      expect(result.enrichment_error).to eq('empty_result')
      expect(result.enrichment_failed_attempts).to eq(1)
    end
  end

  describe 'segundo enriquecimento' do
    before { create_kanban_hook({ 'api_key' => 'chave-da-conta' }) }

    it 'mantém WhatsApp, CNPJ, e-mail, redes e decisor achados antes quando o novo não os traz' do
      lead.update!(
        enriched_email: 'antigo@clinicasorriso.example.com',
        enriched_whatsapp: '+5541911112222',
        enriched_instagram: 'https://instagram.com/antiga',
        enriched_facebook: 'https://facebook.com/antiga',
        enriched_linkedin: 'https://linkedin.com/company/antiga',
        enriched_cnpj: '11.111.111/0001-11',
        decision_name: 'Bruno Lima',
        decision_role: 'Diretor',
        decision_confidence: 0.9,
        decision_source_url: 'https://clinicasorriso.example.com/sobre',
        decision_linkedin: 'https://linkedin.com/in/brunolima',
        enriched_data: { 'cnpj' => '11.111.111/0001-11', 'error' => 'timeout' }
      )
      allow(scraper).to receive(:perform).and_return(
        Autonomia::Prospecting::WebsiteScraper::Result.new(data: { 'title' => 'Clinica Nova', 'text_excerpt' => 'Clinica' })
      )
      allow(ai_client).to receive(:create).and_return(
        { text: ai_payload.merge('decision_name' => nil, 'decision_confidence' => 0).to_json }
      )

      result = enrich

      expect(result).to be_enrichment_completed
      expect(result).to have_attributes(
        enriched_email: 'antigo@clinicasorriso.example.com',
        enriched_whatsapp: '+5541911112222',
        enriched_instagram: 'https://instagram.com/antiga',
        enriched_facebook: 'https://facebook.com/antiga',
        enriched_linkedin: 'https://linkedin.com/company/antiga',
        enriched_cnpj: '11.111.111/0001-11',
        decision_name: 'Bruno Lima',
        decision_role: 'Diretor',
        decision_source_url: 'https://clinicasorriso.example.com/sobre',
        decision_linkedin: 'https://linkedin.com/in/brunolima'
      )
      expect(result.decision_confidence.to_f).to eq(0.9)
      expect(result.enriched_data).to include('title' => 'Clinica Nova', 'cnpj' => '11.111.111/0001-11')
      expect(result.enriched_data).not_to have_key('error')
    end

    it 'troca pelo valor novo quando o site traz outro, sem trocar o decisor' do
      lead.update!(enriched_whatsapp: '+5541911112222', decision_name: 'Bruno Lima', decision_confidence: 0.9)

      result = enrich

      expect(result.enriched_whatsapp).to eq('+5541999990000')
      expect(result.decision_name).to eq('Bruno Lima')
    end
  end

  # Registro de eventos (#732 item 13, ENRIQ-60): log estruturado com lead, conta e motivo, sem dado pessoal.
  describe 'registro de eventos' do
    include ProspectingEventLogHelpers

    let(:personal_data) { ['5541999990000', 'contato@clinicasorriso.example.com', 'chave-da-conta', 'Ana Souza'] }

    before { create_kanban_hook({ 'api_key' => 'chave-da-conta' }) }

    it 'registra o início e a conclusão do enriquecimento, sem telefone, e-mail, chave nem decisor' do
      log = capture_prospecting_events { enrich }

      expect(log.events).to eq(
        [
          { 'event' => 'enrichment.started', 'lead_id' => lead.id, 'account_id' => account.id },
          { 'event' => 'enrichment.completed', 'lead_id' => lead.id, 'account_id' => account.id, 'status' => 'site_and_autonomia_ai' }
        ]
      )
      expect(log.text).not_to include(*personal_data)
    end

    it 'registra a falha com o código do site' do
      allow(scraper).to receive(:perform)
        .and_return(Autonomia::Prospecting::WebsiteScraper::Result.new(data: { 'error' => 'timeout' }))

      log = capture_prospecting_events { enrich }

      expect(log.events.last).to eq('event' => 'enrichment.failed', 'lead_id' => lead.id, 'account_id' => account.id, 'reason' => 'timeout')
    end

    it 'registra a recusa com a pesquisa desligada' do
      Autonomia::Prospecting::Config.disable_research_for!(account)

      log = capture_prospecting_events { expect { enrich }.to raise_error(described_class::Error) }

      expect(log.events).to eq(
        [{ 'event' => 'enrichment.failed', 'lead_id' => lead.id, 'account_id' => account.id, 'reason' => 'prospecting.enrichment.disabled' }]
      )
    end

    it 'de um erro inesperado, registra só a classe: a mensagem pode trazer dado pessoal' do
      allow(scraper).to receive(:perform).and_raise(RuntimeError, 'falhou em contato@clinicasorriso.example.com +5541999990000')

      log = capture_prospecting_events { expect { enrich }.to raise_error(described_class::Error) }

      expect(log.events.last).to eq('event' => 'enrichment.failed', 'lead_id' => lead.id, 'account_id' => account.id, 'reason' => 'RuntimeError')
      expect(log.text).not_to include(*personal_data)
    end

    it 'registra a IA pulada com a classe do erro e segue com o site' do
      allow(ai_client).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error, 'chave-da-conta recusada')

      log = capture_prospecting_events { enrich }

      expect(log.events.pluck('event')).to eq(%w[enrichment.started enrichment.ai_skipped enrichment.completed])
      expect(log.events.second).to include('reason' => 'Crm::Ai::ResponsesClient::Error')
      expect(log.text).not_to include(*personal_data)
    end
  end
end

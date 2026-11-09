require 'rails_helper'

# Reconciliação de um formulário (#2285): lead que o webhook não trouxe entra sozinho; quem já entrou não duplica.
# Queda da Meta fica para a próxima rodada; recusa vai ao rastreador. A trava da rodada sempre sai. Lê desde o mais
# recente entre 48 h atrás, o destino salvo e a Página voltar a receber; marco nulo não lê nada.
RSpec.describe Crm::MetaAds::LeadForms::ReconcileJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:lock_key) { Crm::MetaAds::LeadForms::ReconcileScheduleJob.lock_key(form.id) }
  let!(:form) do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento',
                                 pipeline: pipeline, stage: stage, destination_set_at: 3.days.ago)
  end
  let!(:page) { Crm::MetaAdsPage.create!(account: account, page_id: '104882', leadgen_receiving: true, leadgen_receiving_since: 3.days.ago) }

  before do
    allow(Rails).to receive(:cache).and_return(cache)
    cache.write(lock_key, true)
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 200, headers: json, body: { access_token: 'page-token' }.to_json)
    stub_request(:get, meta_graph_url('9001')).with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
                                              .to_return(status: 200, headers: json, body: { id: '9001', questions: [] }.to_json)
  end

  def lead(id, name, phone)
    { id: id, created_time: 1.hour.ago.iso8601, form_id: '9001',
      field_data: [{ name: 'full_name', values: [name] }, { name: 'phone_number', values: [phone] }] }
  end

  def stub_leads(status: 200, leads: [lead('L1', 'Ana', '+5511987650001')])
    error_code = status == 400 ? 100 : 1
    body = status == 200 ? { data: leads } : meta_graph_error(error_code)
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: status, headers: json, body: body.to_json)
  end

  it 'traz para o destino o lead que o webhook não trouxe, lendo só as últimas 48 h' do
    stub_leads
    since = nil

    freeze_time do
      since = 48.hours.ago.to_i
      described_class.perform_now(form.id)
    end

    expect(account.crm_cards.where(stage: stage).pluck(:title)).to eq(['Ana'])
    filtering = [{ field: 'time_created', operator: 'GREATER_THAN', value: since }].to_json
    expect(a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering))).to have_been_made.once
  end

  def filtering(since)
    [{ field: 'time_created', operator: 'GREATER_THAN', value: since.to_i }].to_json
  end

  def read_since?(since)
    a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering(since)))
  end

  # A Meta filtra pelo time_created: aqui ela devolve o lead de 1 h atrás só para quem pede as 48 h.
  def stub_leads_by_since(old_since, new_since)
    old = { data: [lead('L1', 'Ana', '+5511987650001')] }
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering(old_since)))
                                                    .to_return(status: 200, headers: json, body: old.to_json)
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including('filtering' => filtering(new_since)))
                                                    .to_return(status: 200, headers: json, body: { data: [] }.to_json)
  end

  it 'destino salvo depois do lead: lê só desde o destino, e o lead de antes não entra' do
    freeze_time do
      form.update!(destination_set_at: 30.minutes.ago)
      stub_leads_by_since(48.hours.ago, 30.minutes.ago)

      described_class.perform_now(form.id)

      expect(read_since?(30.minutes.ago)).to have_been_made.once
      expect(account.crm_cards.count).to eq(0)
    end
  end

  it 'Página parada e religada: lê só desde que voltou a receber, e o lead do período parado não entra' do
    freeze_time do
      page.update!(leadgen_receiving_since: 10.minutes.ago)
      stub_leads_by_since(48.hours.ago, 10.minutes.ago)

      described_class.perform_now(form.id)

      expect(read_since?(10.minutes.ago)).to have_been_made.once
      expect(account.crm_cards.count).to eq(0)
    end
  end

  it 'fila atrasada: Página parada e religada com o job na fila; o marco é lido quando o job roda' do
    stub_leads
    described_class.perform_later(form.id)

    travel_to(2.hours.from_now) do
      page.update!(leadgen_receiving_since: 5.minutes.ago)

      perform_enqueued_jobs

      expect(read_since?(5.minutes.ago)).to have_been_made.once
    end
  end

  it 'lead que já entrou não passa pelo Importer nem faz ler as perguntas' do
    stub_leads
    described_class.perform_now(form.id)
    WebMock.reset_executed_requests!
    allow(Crm::MetaAds::LeadForms::Importer).to receive(:new).and_call_original

    described_class.perform_now(form.id)

    expect(Crm::MetaAds::LeadForms::Importer).not_to have_received(:new)
    expect(a_request(:get, meta_graph_url('9001')).with(query: hash_including({}))).not_to have_been_made
  end

  it 'destino sem marco (linha de antes do #2285): não chama a Meta e solta a trava' do
    form.update!(destination_set_at: nil)

    described_class.perform_now(form.id)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(cache.exist?(lock_key)).to be(false)
  end

  it 'Página sem marco: não chama a Meta' do
    page.update!(leadgen_receiving_since: nil)

    described_class.perform_now(form.id)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end

  it 'lead que já entrou pelo webhook não duplica; só o que faltava vira card' do
    stub_leads
    described_class.perform_now(form.id)
    stub_leads(leads: [lead('L1', 'Ana', '+5511987650001'), lead('L2', 'Bia', '+5511987650002')])

    described_class.perform_now(form.id)

    expect(account.crm_cards.order(:id).pluck(:title)).to eq(%w[Ana Bia])
    expect(Crm::MetaAdsLead.where(account: account).pluck(:leadgen_id)).to contain_exactly('L1', 'L2')
  end

  it 'rodada sem lead novo: não lê as perguntas do formulário (só o token da Página e a lista de leads)' do
    stub_leads(leads: [])

    described_class.perform_now(form.id)

    expect(a_request(:get, meta_graph_url('9001')).with(query: hash_including({}))).not_to have_been_made
    expect(a_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))).to have_been_made.once
  end

  it 'solta a trava da rodada no fim' do
    stub_leads

    described_class.perform_now(form.id)

    expect(cache.exist?(lock_key)).to be(false)
  end

  it 'Meta fora do ar: não cria card, não vai ao rastreador e solta a trava (a próxima rodada relê)' do
    stub_leads(status: 500)
    allow(ChatwootExceptionTracker).to receive(:new)

    expect { described_class.perform_now(form.id) }.not_to raise_error

    expect(account.crm_cards.count).to eq(0)
    expect(ChatwootExceptionTracker).not_to have_received(:new)
    expect(cache.exist?(lock_key)).to be(false)
  end

  it 'Meta recusa ler: vai ao rastreador com o form_id e o código, uma vez por dia' do
    stub_leads(status: 400)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    2.times { described_class.perform_now(form.id) }

    expect(ChatwootExceptionTracker).to have_received(:new)
      .with(having_attributes(message: include('form_id=9001').and(include('code=meta_refused'))), account: account).once
    expect(cache.exist?(lock_key)).to be(false)
  end

  # #2740: recusa de token na reconciliação marca a conexão, como o webhook faz. A rodada seguinte nem chama a Meta.
  describe 'token recusado pela Meta (190)' do
    def token_recusado(path, query)
      stub_request(:get, meta_graph_url(path)).with(query: query)
                                              .to_return(status: 400, headers: json, body: meta_graph_error(190, 'Token expirado').to_json)
    end

    it 'ao tirar o token da Página: a conexão fica inválida, sem rastreador, e a próxima rodada não chama a Meta',
       :aggregate_failures do
      token_recusado('104882', { fields: 'access_token' })
      allow(ChatwootExceptionTracker).to receive(:new)

      described_class.perform_now(form.id)

      expect(Crm::MetaAdsConnection.find_by(account: account)).to have_attributes(status: 'invalid', last_error: be_present)
      expect(ChatwootExceptionTracker).not_to have_received(:new)
      expect(cache.exist?(lock_key)).to be(false)

      WebMock.reset_executed_requests!
      described_class.perform_now(form.id)
      expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    end

    it 'ao ler os leads com o token da Página: a conexão fica inválida, sem rastreador' do
      token_recusado('9001/leads', hash_including({}))
      allow(ChatwootExceptionTracker).to receive(:new)

      described_class.perform_now(form.id)

      expect(Crm::MetaAdsConnection.find_by(account: account).status).to eq('invalid')
      expect(ChatwootExceptionTracker).not_to have_received(:new)
    end

    it 'recusa que não é de token (permissão): a conexão continua ativa' do
      stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                      .to_return(status: 400, headers: json, body: meta_graph_error(200).to_json)

      described_class.perform_now(form.id)

      expect(Crm::MetaAdsConnection.find_by(account: account).status).to eq('active')
    end
  end

  # #2740: lead que o banco recusa (dado inválido) não é tentado de novo a cada hora; vai ao rastreador uma vez.
  describe 'lead que não dá para gravar' do
    let(:recusa) { ActiveRecord::RecordInvalid.new(Crm::Card.new) }

    it 'a rodada seguinte não tenta de novo, e o lead novo bom entra', :aggregate_failures do
      stub_leads(leads: [lead('L1', 'Ana', '+5511987650001')])
      allow_any_instance_of(Crm::Cards::Creator).to receive(:perform).and_raise(recusa) # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))

      described_class.perform_now(form.id)
      expect(account.crm_cards.count).to eq(0)

      allow_any_instance_of(Crm::Cards::Creator).to receive(:perform).and_call_original # rubocop:disable RSpec/AnyInstance
      stub_leads(leads: [lead('L1', 'Ana', '+5511987650001'), lead('L2', 'Bia', '+5511987650002')])
      allow(Crm::MetaAds::LeadForms::Importer).to receive(:new).and_call_original

      2.times { described_class.perform_now(form.id) }

      expect(account.crm_cards.pluck(:title)).to eq(['Bia'])
      expect(Crm::MetaAdsLead.where(account: account).pluck(:leadgen_id)).to eq(['L2'])
      expect(ChatwootExceptionTracker).to have_received(:new).once
    end

    def recusar_ana!
      stub_leads(leads: [lead('L1', 'Ana', '+5511987650001')])
      allow_any_instance_of(Crm::Cards::Creator).to receive(:perform).and_raise(recusa) # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
      described_class.perform_now(form.id)
      allow_any_instance_of(Crm::Cards::Creator).to receive(:perform).and_call_original # rubocop:disable RSpec/AnyInstance
    end

    # A recusa pode ser do destino (funil ou etapa): consertado e salvo de novo, o lead bom não fica preso.
    it 'destino salvo de novo: a rodada seguinte tenta de novo e o lead entra' do
      recusar_ana!

      travel(1.second) { form.update!(updated_at: Time.current) } # o Hub muda a linha ao salvar o destino (hub_spec)
      described_class.perform_now(form.id)

      expect(account.crm_cards.pluck(:title)).to eq(['Ana'])
    end

    it 'passado o prazo da recusa, a reconciliação tenta de novo' do
      recusar_ana!

      travel_to((Crm::MetaAds::LeadForms::RefusedLeads::TTL + 1.minute).from_now) do
        cache.write(lock_key, true)
        described_class.perform_now(form.id)
      end

      expect(account.crm_cards.pluck(:title)).to eq(['Ana'])
    end

    it 'lead só com recusa: a rodada seguinte nem lê as perguntas do formulário' do
      stub_leads(leads: [lead('L1', 'Ana', '+5511987650001')])
      allow_any_instance_of(Crm::Cards::Creator).to receive(:perform).and_raise(recusa) # rubocop:disable RSpec/AnyInstance
      allow(ChatwootExceptionTracker).to receive(:new).and_return(instance_double(ChatwootExceptionTracker, capture_exception: true))
      described_class.perform_now(form.id)
      WebMock.reset_executed_requests!

      described_class.perform_now(form.id)

      expect(a_request(:get, meta_graph_url('9001')).with(query: hash_including({}))).not_to have_been_made
    end
  end

  it 'Página parada depois do agendamento: não chama a Meta e solta a trava' do
    Crm::MetaAdsPage.find_by(account: account).update!(leadgen_receiving: false)

    described_class.perform_now(form.id)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(cache.exist?(lock_key)).to be(false)
  end

  it 'conta sem a flag: não chama a Meta' do
    account.disable_features!('meta_ads_formularios')

    described_class.perform_now(form.id)

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
  end
end

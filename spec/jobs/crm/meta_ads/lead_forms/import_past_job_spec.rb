require 'rails_helper'

# "Trazer quem já preencheu" em segundo plano (#2195): cria os cards na etapa, não duplica ao rodar de novo, e todo fim
# fica na Auditoria (quantos entraram, ou o motivo de não trazer). Falha na leitura não desfaz o destino do formulário.
RSpec.describe Crm::MetaAds::LeadForms::ImportPastJob do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pipeline_and_stage) { create_crm_pipeline(account: account, user: admin) }
  let(:pipeline) { pipeline_and_stage.first }
  let(:stage) { pipeline_and_stage.last }
  let(:json) { { 'Content-Type' => 'application/json' } }
  let!(:form) do
    Crm::MetaAdsLeadForm.create!(account: account, page_id: '104882', form_id: '9001', form_name: 'Orçamento',
                                 pipeline: pipeline, stage: stage)
  end

  before do
    account.enable_features!('meta_ads_formularios')
    create_meta_ads_insights_connection(account)
    stub_request(:get, meta_graph_url('104882')).with(query: { fields: 'access_token' })
                                                .to_return(status: 200, headers: json, body: { access_token: 'page-token' }.to_json)
    stub_request(:get, meta_graph_url('9001')).with(query: { fields: Meta::AdsGraphClient::LEAD_FORM_QUESTION_FIELDS })
                                              .to_return(status: 200, headers: json, body: { id: '9001', questions: [] }.to_json)
  end

  def stub_leads(status: 200)
    body = if status == 200
             { data: [{ id: 'L1', created_time: '2026-10-20T12:00:00+0000', form_id: '9001',
                        field_data: [{ name: 'full_name', values: ['Ana'] }, { name: 'phone_number', values: ['+5511987650001'] }] }] }
           else
             meta_graph_error(status == 400 ? 100 : 1)
           end
    stub_request(:get, meta_graph_url('9001/leads')).with(query: hash_including({}))
                                                    .to_return(status: status, headers: json, body: body.to_json)
  end

  def run(**)
    described_class.perform_now(account.id, '104882', '9001', pipeline.id, stage.id, user_id: admin.id, **)
  end

  def last_audit
    Audited.audit_class.where(auditable: account, action: 'meta_ads_lead_form_past_imported').last
  end

  it 'traz quem preencheu para a etapa e deixa na Auditoria quem pediu e quantos entraram' do
    stub_leads

    run

    expect(account.crm_cards.where(stage: stage).pluck(:title)).to eq(['Ana'])
    expect(last_audit).to have_attributes(user_id: admin.id)
    expect(last_audit.audited_changes).to include('form_id' => '9001', 'imported' => 1, 'truncated' => false)
  end

  it 'rodar de novo não duplica: o mesmo leadgen_id não cria outro card' do
    stub_leads

    2.times { run }

    expect(account.crm_cards.count).to eq(1)
    expect(last_audit.audited_changes).to include('imported' => 0)
  end

  it 'trazer de formulário arquivado soma em brought_count' do
    stub_leads

    run(brought: true)

    expect(form.reload.brought_count).to eq(1)
  end

  it 'a Meta recusa ler: a Auditoria registra e o destino do formulário fica' do
    stub_leads(status: 400)

    run

    expect(last_audit.audited_changes).to include('import_error' => 'meta_refused')
    expect(form.reload).to have_attributes(pipeline_id: pipeline.id, stage_id: stage.id)
  end

  it 'funil arquivado entre o clique e o job: não traz ninguém e a Auditoria diz por quê' do
    pipeline.update!(status: :archived)

    run

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(last_audit.audited_changes).to include('import_error' => 'destination_gone')
  end

  it 'sem a flag: não chama a Meta nem audita' do
    account.disable_features!('meta_ads_formularios')

    run

    expect(a_request(:any, /graph\.facebook\.com/)).not_to have_been_made
    expect(last_audit).to be_nil
  end

  it 'Meta fora do ar nas 5 tentativas: a Auditoria diz que não trouxe e o form_id vai ao rastreador' do
    stub_leads(status: 500)
    tracker = instance_double(ChatwootExceptionTracker, capture_exception: true)
    allow(ChatwootExceptionTracker).to receive(:new).and_return(tracker)

    perform_enqueued_jobs do
      described_class.perform_later(account.id, '104882', '9001', pipeline.id, stage.id, user_id: admin.id)
    end

    expect(ChatwootExceptionTracker).to have_received(:new).with(having_attributes(message: include('form_id=9001')), account: account)
    expect(last_audit.audited_changes).to include('import_error' => 'meta_unavailable')
    expect(last_audit).to have_attributes(user_id: admin.id)
    expect(form.reload.pipeline_id).to eq(pipeline.id)
  end
end

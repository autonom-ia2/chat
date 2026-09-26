require 'rails_helper'

# Recusa depois do segmento (#732, revisão da E8): as duas campanhas leem o público pela etiqueta do segmento, a de
# envio único no disparo (tagged_with) e a da API do WhatsApp ao começar (AudienceResolver). Quem é descartado ou marcado
# como recusado depois de receber a etiqueta perde a etiqueta no job da Prospecção (SegmentRefusalSyncJob), que a
# recusa enfileira depois de gravada. A resposta da recusa não depende da etiqueta. O contato que outro lead elegível da
# lista ainda alcança fica com ela.
RSpec.describe 'Autonomia prospecting refusal after segment', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:inbox) { create_whatsapp_api_inbox(account: account) }
  let(:campaign) do
    create_whatsapp_api_campaign(account: account, user: admin, inbox: inbox, label: account.labels.create!(title: 'base'))
  end
  let(:list) { Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Selecao') }
  let(:sync_job) { Autonomia::Prospecting::SegmentRefusalSyncJob }

  around do |example|
    with_modified_env('WHATSAPP_API_CAMPAIGNS_ENABLED' => 'true') { example.run }
  end

  before { Autonomia::Prospecting::Config.enable_for!(account) }

  def create_lead(name, phone, in_list: true, **attributes)
    lead = Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: "refusal-#{name}", name: name, phone: phone, country: 'BR',
      status: :ready_for_campaign, metadata: { 'whatsapp_verification' => { 'status' => 'verified', 'phone' => phone } },
      **attributes
    )
    list.list_leads.create!(account: account, lead: lead) if in_list
    lead
  end

  def generate_segment
    post "#{base_url}/lists/#{list.id}/campaign_segment",
         params: { campaign_segment: { campaign_id: campaign.id, campaign_type: 'whatsapp_api', segment_name: 'Selecao' } },
         headers: auth_headers(admin), as: :json
    expect(response).to have_http_status(:created)
    response.parsed_body.dig('payload', 'segment', 'label', 'title')
  end

  def patch_status(lead, attributes)
    patch "#{base_url}/leads/#{lead.id}", params: { lead: attributes }, headers: auth_headers(admin), as: :json
  end

  def discard(leads, reason = 'Sem interesse')
    post "#{base_url}/leads/discard", params: { lead_ids: leads.map(&:id), reason: reason }, headers: auth_headers(admin), as: :json
  end

  def run_sync_jobs
    perform_enqueued_jobs(only: sync_job)
  end

  def recipients_names
    WhatsappApiCampaigns::AudienceResolver.new(campaign.reload).perform
    campaign.whatsapp_api_campaign_recipients.map { |recipient| recipient.contact.name }
  end

  def one_off_audience(label_title)
    account.contacts.tagged_with([label_title], any: true).map(&:name)
  end

  def labels_of(lead)
    lead.reload.contact.reload.label_list
  end

  def break_contact_email(lead)
    lead.reload.contact.update_columns(email: 'nao-e-email') # rubocop:disable Rails/SkipsModelValidations
  end

  it 'PATCH para recusado responde sem esperar a etiqueta e enfileira o job que a tira' do
    create_lead('Pronto', '+5531999990001')
    refused = create_lead('Depois recusou', '+5531999990002')
    label_title = generate_segment

    patch_status(refused, status: 'no_consent')

    expect(response).to have_http_status(:ok)
    expect(sync_job).to have_been_enqueued.with(account.id, [refused.id]).on_queue('medium')
    expect(labels_of(refused)).to include(label_title)

    run_sync_jobs

    expect(labels_of(refused)).not_to include(label_title)
    expect(one_off_audience(label_title)).to eq(['Pronto'])
    expect(recipients_names).to eq(['Pronto'])
  end

  it 'PATCH para descartado tira a etiqueta' do
    create_lead('Pronto', '+5531999990001')
    discarded = create_lead('Descartado', '+5531999990002')
    label_title = generate_segment

    patch_status(discarded, status: 'discarded', discard_reason: 'Sem interesse')
    run_sync_jobs

    expect(response).to have_http_status(:ok)
    expect(labels_of(discarded)).not_to include(label_title)
  end

  it 'descarte em lote enfileira um job com os leads e tira a etiqueta de todos os descartados' do
    create_lead('Pronto', '+5531999990001')
    first = create_lead('Descartado 1', '+5531999990002')
    second = create_lead('Descartado 2', '+5531999990003')
    label_title = generate_segment

    discard([first, second])

    expect(response).to have_http_status(:ok)
    expect(sync_job).to have_been_enqueued.once.with(account.id, [first.id, second.id])

    run_sync_jobs

    expect(one_off_audience(label_title)).to eq(['Pronto'])
    expect(recipients_names).to eq(['Pronto'])
  end

  it 'o contato que outro lead elegível da lista ainda alcança fica com a etiqueta, e o do outro descartado sai' do
    create_lead('Pronto', '+5531999990001')
    duplicate = create_lead('Mesmo numero', '+5531999990001')
    alone = create_lead('Numero proprio', '+5531999990002')
    label_title = generate_segment

    discard([duplicate, alone], 'Duplicado')
    run_sync_jobs

    expect(response).to have_http_status(:ok)
    expect(labels_of(duplicate)).to include(label_title)
    expect(labels_of(alone)).not_to include(label_title)
  end

  it 'recusa de um lead fora da lista, pelo mesmo número, tira a etiqueta do contato da lista' do
    in_list = create_lead('Na lista', '+5531999990001')
    label_title = generate_segment
    outside = create_lead('Outra unidade', '+5531999990001', in_list: false)

    patch_status(outside, status: 'no_consent')
    run_sync_jobs

    expect(response).to have_http_status(:ok)
    expect(labels_of(in_list)).not_to include(label_title)
    expect(recipients_names).to eq([])
  end

  it 'recusa pelo WhatsApp do site tira a etiqueta do outro contato da lista com esse número' do
    unidade = create_lead('Unidade', '+5531999990002')
    matriz = create_lead('Matriz', '+5531999990001', enriched_whatsapp: '+5531999990002')
    label_title = generate_segment
    expect(unidade.reload.contact_id).not_to eq(matriz.reload.contact_id)

    patch_status(matriz, status: 'no_consent')
    run_sync_jobs

    expect(labels_of(unidade)).not_to include(label_title)
    expect(labels_of(matriz)).not_to include(label_title)
    expect(recipients_names).to eq([])
  end

  it 'lista que ficou sem nenhum lead elegível também perde a etiqueta' do
    only = create_lead('Unico', '+5531999990001')
    label_title = generate_segment

    patch_status(only, status: 'no_consent')
    run_sync_jobs

    expect(labels_of(only)).not_to include(label_title)
    expect(one_off_audience(label_title)).to eq([])
  end

  it 'mudança que não é recusa não enfileira o job nem mexe na etiqueta' do
    lead = create_lead('Pronto', '+5531999990001')
    label_title = generate_segment

    patch_status(lead, status: 'qualified')

    expect(response).to have_http_status(:ok)
    expect(sync_job).not_to have_been_enqueued

    Autonomia::Prospecting::SegmentRefusalSyncJob.perform_now(account.id, [lead.id])

    expect(labels_of(lead)).to include(label_title)
  end

  # Contato gravado antes com e-mail que o Contact hoje recusa: salvar o contato inteiro falharia.
  it 'contato inválido: o PATCH grava a recusa e responde 200, e o job tira a etiqueta mesmo assim' do
    refused = create_lead('Contato quebrado', '+5531999990002')
    create_lead('Pronto', '+5531999990001')
    label_title = generate_segment
    break_contact_email(refused)

    patch_status(refused, status: 'no_consent')

    expect(response).to have_http_status(:ok)
    expect(refused.reload.status).to eq('no_consent')

    run_sync_jobs

    expect(labels_of(refused)).not_to include(label_title)
  end

  it 'contato inválido no lote não impede a resposta nem a remoção dos outros' do
    broken = create_lead('Contato quebrado', '+5531999990002')
    healthy = create_lead('Contato bom', '+5531999990003')
    create_lead('Pronto', '+5531999990001')
    label_title = generate_segment
    break_contact_email(broken)

    discard([broken, healthy])

    expect(response).to have_http_status(:ok)

    run_sync_jobs

    expect(labels_of(broken)).not_to include(label_title)
    expect(labels_of(healthy)).not_to include(label_title)
    expect(one_off_audience(label_title)).to eq(['Pronto'])
  end
end

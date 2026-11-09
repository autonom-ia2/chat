require 'rails_helper'

# A tela mostra `error` como veio do servidor (#682): toda recusa da Prospecção sai com frase em português, do I18n, e o
# código de máquina, quando existe, vai em `code`. Antes, estes caminhos devolviam código cru ou texto em inglês.
RSpec.describe 'Autonomia prospecting error messages', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, :administrator, account: account) }
  let(:base_url) { "/api/v1/accounts/#{account.id}/autonomia/prospecting" }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(account: account, provider: 'mock', provider_place_id: 'place-msg-1', name: 'Padaria',
                                         phone: '+55 31 99999-0001', country: 'BR')
  end

  before do
    Autonomia::Prospecting::Config.enable_for!(account)
    allow(Crm::Config).to receive(:enabled?).and_return(true)
  end

  def error_and_code
    response.parsed_body.slice('error', 'code')
  end

  it 'busca com quantidade zero recusa com a frase, sem o nome do atributo em inglês' do
    post "#{base_url}/searches", params: { search: { query: 'padaria', requested_limit: 0 } }, headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.errors.limit_invalid'))
  end

  it 'destino de CRM que não existe na busca salva responde com a frase do funil' do
    search = Autonomia::Prospecting::Search.create!(account: account, user: admin, query: 'padaria', requested_limit: 1)

    patch "#{base_url}/searches/#{search.id}", params: { search: { crm_pipeline_id: 0, crm_stage_id: 0 } }, headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
    expect(error_and_code).to eq('error' => I18n.t('autonomia.prospecting.crm_send.errors.pipeline_not_found'),
                                 'code' => 'prospecting.crm_send.pipeline_not_found')
  end

  it 'envio individual ao CRM para funil que não existe responde com a frase do funil' do
    post "#{base_url}/leads/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: 0, stage_id: 0 } },
                                                  headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:not_found)
    expect(error_and_code).to eq('error' => I18n.t('autonomia.prospecting.crm_send.errors.pipeline_not_found'),
                                 'code' => 'prospecting.crm_send.pipeline_not_found')
  end

  it 'envio individual ao CRM com o CRM desligado responde com a frase, não com o texto da exceção' do
    allow(Crm::Config).to receive(:enabled?).and_return(false)
    pipeline, stage = create_crm_pipeline(account: account, user: admin)

    post "#{base_url}/leads/#{lead.id}/crm_card", params: { crm_card: { pipeline_id: pipeline.id, stage_id: stage.id } },
                                                  headers: auth_headers(admin), as: :json

    expect(response.parsed_body['error']).not_to include('CRM is disabled')
    expect(response.parsed_body['error']).to be_present
  end

  it 'adicionar lead à lista sem escolher o lead responde com a frase' do
    list = Autonomia::Prospecting::List.create!(account: account, user: admin, name: 'Lista')

    post "#{base_url}/lists/#{list.id}/leads", headers: auth_headers(admin), as: :json

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body['error']).to eq(I18n.t('autonomia.prospecting.errors.lead_required'))
  end

  it 'as frases existem em en e em pt_BR, iguais' do
    keys = %w[errors.disabled errors.enrichment_disabled errors.query_required errors.limit_invalid errors.limit_too_high
              errors.unsupported_provider errors.lead_required campaign_errors.forbidden audience.errors.no_leads
              audience.errors.too_many_leads audience.errors.no_rows audience.errors.foreign_contact audience.errors.contacts_saved
              audience.left_out.same_contact audience.left_out.already_in_list audience.left_out.blocked
              audience.left_out.unreachable audience.errors.audience_locked audience.errors.not_audience
              audience.errors.no_members audience.errors.all_already_in_list audience.errors.too_many_members
              audience.errors.invalid_cursor]

    keys.each do |key|
      english = I18n.t("autonomia.prospecting.#{key}", locale: :en, max: 1, raise: true)
      expect(I18n.t("autonomia.prospecting.#{key}", locale: :pt_BR, max: 1, raise: true)).to eq(english)
    end
  end
end

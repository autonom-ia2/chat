# frozen_string_literal: true

require 'rails_helper'

# #1550 — a requisição da conta usa o pacote de tradução dela, e o pacote não vaza para a próxima requisição.
RSpec.describe 'Pacote de tradução da conta nas requisições', type: :request do
  let(:nicho) { Autonomia::Agents::Nicho }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run }
  ensure
    ActiveSupport::IsolatedExecutionState.delete(AutonomiaPacotesI18nLookup::ESTADO)
  end

  def conta_com_card_ganho(nicho_escolhido, perfil = nil)
    account, admin = create_account_and_user
    escolha = { nicho::NICHO_KEY => nicho_escolhido, nicho::PERFIL_KEY => perfil }.compact
    account.update!(locale: 'pt_BR', internal_attributes: account.internal_attributes.to_h.merge(escolha))
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Seguro auto', status: :won)
    [account, admin, pipeline]
  end

  def status_exportado(account, admin, pipeline)
    get "/api/v1/accounts/#{account.id}/crm/cards/export", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    Roo::Excelx.new(StringIO.new(response.body)).sheet(0).cell(Crm::Cards::XlsxExport::HEADER_ROW + 1, 4)
  end

  it 'exporta com o texto do pacote na conta de seguros e com o geral na conta seguinte, sem vazar' do
    seguros = conta_com_card_ganho('seguros', 'corretora')
    geral = conta_com_card_ganho('geral')

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(status_exportado(*seguros)).to eq('Seguro ativo')
      expect(Autonomia::Segmentos::Pacotes.ativas).to eq([])

      expect(status_exportado(*geral)).to eq('Ganho')
      expect(Autonomia::Segmentos::Pacotes.ativas).to eq([])
    end
  end

  it 'exporta o nome que o funil deu ao desfecho, acima do pacote' do
    account, admin, pipeline = conta_com_card_ganho('seguros', 'corretora')
    pipeline.update!(metadata: pipeline.metadata.merge('outcome_labels' => { 'success' => 'Apólice emitida' }))

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
      expect(status_exportado(account, admin, pipeline)).to eq('Apólice emitida')
    end
  end

  # Pedido do Multifunnel: o nome do funil vale só para o desfecho; card aberto segue o texto do idioma.
  it 'exporta o nome do funil no card ganho e o texto do idioma no card aberto' do
    account, admin, pipeline = conta_com_card_ganho('geral')
    pipeline.update!(metadata: pipeline.metadata.merge('outcome_labels' => { 'success' => 'Contratado' }))
    account.crm_cards.create!(pipeline: pipeline, stage: pipeline.stages.first, title: 'Seguro vida', status: :open)

    get "/api/v1/accounts/#{account.id}/crm/cards/export", params: { pipeline_id: pipeline.id }, headers: auth_headers(admin)
    planilha = Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
    linhas = (1..2).map { |i| planilha.cell(Crm::Cards::XlsxExport::HEADER_ROW + i, 4) }

    expect(linhas).to contain_exactly('Contratado', I18n.t('crm.export.statuses.open', locale: :pt_BR))
  end

  it 'exporta com o geral quando o interruptor está desligado' do
    seguros = conta_com_card_ganho('seguros', 'corretora')

    with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
      expect(status_exportado(*seguros)).to eq('Ganho')
    end
  end

  describe 'GET /api/v1/accounts/:id' do
    it 'traz o nome do pacote da conta' do
      account, admin, = conta_com_card_ganho('seguros', 'corretora')

      with_modified_env(AUTONOMIA_PACOTES_ENABLED: 'true') do
        get "/api/v1/accounts/#{account.id}", headers: auth_headers(admin), as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body['autonomia_pacote']).to eq('seguros.corretora')
    end

    it 'traz nil com o interruptor desligado' do
      account, admin, = conta_com_card_ganho('seguros', 'corretora')

      with_modified_env(AUTONOMIA_PACOTES_ENABLED: nil) do
        get "/api/v1/accounts/#{account.id}", headers: auth_headers(admin), as: :json
      end

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to have_key('autonomia_pacote')
      expect(response.parsed_body['autonomia_pacote']).to be_nil
    end
  end
end

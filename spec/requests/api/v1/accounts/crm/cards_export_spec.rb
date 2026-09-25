require 'rails_helper'

# #722 — planilha (.xlsx) da Lista do CRM: o mesmo recorte da Lista, sem página.
RSpec.describe 'CRM cards export', type: :request do
  around do |example|
    previous_value = ENV.fetch('CRM_KANBAN_ENABLED', nil)
    ENV['CRM_KANBAN_ENABLED'] = 'true'
    example.run
  ensure
    previous_value.nil? ? ENV.delete('CRM_KANBAN_ENABLED') : ENV['CRM_KANBAN_ENABLED'] = previous_value
  end

  def exportar(account, user, params = {})
    get "/api/v1/accounts/#{account.id}/crm/cards/export", params: params, headers: auth_headers(user)
  end

  def planilha
    Roo::Excelx.new(StringIO.new(response.body)).sheet(0)
  end

  # Linhas 1-2: título e resumo; 3: respiro; 4: cabeçalho; dados a partir da 5.
  def cabecalho = Crm::Cards::XlsxExport::HEADER_ROW
  def primeira = cabecalho + 1

  def titulos
    (primeira..planilha.last_row.to_i).map { |linha| planilha.cell(linha, 1) }
  end

  def card!(account, pipeline, stage, title, **attrs)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: title, **attrs)
  end

  context 'with a complete card in a Portuguese account' do
    let(:conta_e_admin) { create_account_and_user }
    let(:account) { conta_e_admin.first.tap { |conta| conta.update!(locale: 'pt_BR') } }
    let(:admin) { conta_e_admin.last }
    let(:pipeline) { create_crm_pipeline(account: account, user: admin).first }

    before do
      contact = account.contacts.create!(name: 'Maria Lead', phone_number: '+5511987654321', email: 'maria@lead.test',
                                         additional_attributes: { 'company_name' => 'Acme' })
      atributos = { contact: contact, value_cents: 150_050, priority: :high, owner: admin }
      card!(account, pipeline, pipeline.stages.first, 'Seguro auto', **atributos)
    end

    it 'baixa um .xlsx com o funil no título, o resumo e o cabeçalho no idioma da conta' do
      exportar(account, admin, pipeline_id: pipeline.id)

      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Type']).to include('spreadsheetml')
      expect(response.headers['Content-Disposition']).to include('attachment').and include('.xlsx')
      expect(planilha.cell(1, 1)).to eq('Funil Comercial')
      expect(planilha.cell(2, 1)).to start_with('Exportado em ').and end_with('· 1 card')
      expect(planilha.row(cabecalho).first(5)).to eq(%w[Título Funil Etapa Status Valor])
    end

    it 'traz os dados do card e do contato, com valor como número' do
      exportar(account, admin, pipeline_id: pipeline.id)

      linha = planilha.row(primeira)
      expect(linha.first(7)).to eq(['Seguro auto', 'Funil Comercial', 'Novo Lead', 'Aberto', 1500.5, 'BRL', 'Alta'])
      expect(linha[7..11]).to eq(['Maria Lead', '+5511987654321', 'maria@lead.test', 'Acme', 'Admin User'])
    end
  end

  it 'respeita o funil, o filtro, a busca e a ordem da Lista' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    outra_etapa = create_crm_stage(account: account, pipeline: pipeline, name: 'Proposta')
    outro_funil, etapa_do_outro = create_crm_pipeline(account: account, user: admin, name: 'Outro funil')
    card!(account, pipeline, stage, 'Seguro barato', value_cents: 1_000)
    card!(account, pipeline, stage, 'Seguro caro', value_cents: 9_000)
    card!(account, pipeline, outra_etapa, 'Seguro em proposta', value_cents: 5_000)
    card!(account, pipeline, stage, 'Plano de saúde', value_cents: 7_000)
    card!(account, outro_funil, etapa_do_outro, 'Seguro de outro funil', value_cents: 8_000)

    exportar(account, admin, pipeline_id: pipeline.id, stage_ids: stage.id.to_s, search: 'seguro',
                             sort: 'value_cents', direction: 'desc')

    expect(titulos).to eq(['Seguro caro', 'Seguro barato'])
  end

  it 'traz todos os cards, sem o limite de página da Lista' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    total = Api::V1::Accounts::Crm::CardsController::MAX_RESULTS_PER_PAGE + 5
    total.times { |indice| card!(account, pipeline, stage, "Card #{indice}") }

    exportar(account, admin, pipeline_id: pipeline.id)

    expect(titulos.size).to eq(total)
  end

  it 'grava como texto o que começa com =, sem virar fórmula' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    card!(account, pipeline, stage, '=HYPERLINK("https://mal.test","clique")')

    exportar(account, admin, pipeline_id: pipeline.id)

    expect(planilha.formula(primeira, 1)).to be_nil
    expect(planilha.cell(primeira, 1)).to eq('=HYPERLINK("https://mal.test","clique")')
  end

  # Arquivo fora do schema abre no Excel com "encontramos um problema, deseja reparar?".
  it 'gera um arquivo válido no schema do Excel, inclusive sem nenhum card' do
    account, admin = create_account_and_user
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    admin_seat = account.account_users.find_by(user: admin)
    vazio = Crm::Cards::XlsxExport.new(cards: account.crm_cards.none, account: account, user: admin,
                                       account_user: admin_seat, pipeline: pipeline)
    card!(account, pipeline, stage, 'Seguro auto', value_cents: 10_000, priority: :urgent)
    cheio = Crm::Cards::XlsxExport.new(cards: account.crm_cards.all, account: account, user: admin,
                                       account_user: admin_seat, pipeline: pipeline)

    expect(vazio.package.validate).to be_empty
    expect(cheio.package.validate).to be_empty
  end

  it 'recusa o agente sem permissão de exportar' do
    account, admin = create_account_and_user
    agent, = create_crm_agent(account: account)
    pipeline, = create_crm_pipeline(account: account, user: admin)

    exportar(account, agent, pipeline_id: pipeline.id)

    expect(response).to have_http_status(:unauthorized)
  end
end

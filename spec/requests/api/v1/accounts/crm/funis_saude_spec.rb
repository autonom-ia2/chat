require 'rails_helper'

# #2083: os funis da saúde. A "Venda de plano" é o modelo VENDAS com as frases da saúde (pacote
# seguros/saude_beneficios); a Carteira (Atender) é modelo novo, com o critério no catálogo base.
RSpec.describe 'CRM funis da saúde (#2083)', type: :request do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:saude) do
    create(:account, locale: 'pt_BR', internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'saude_beneficios' })
  end
  let(:geral) { create(:account, locale: 'pt_BR') }

  around do |example|
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
    with_modified_env(CRM_KANBAN_ENABLED: 'true', CRM_AI_ENABLED: 'true', AUTONOMIA_PACOTES_ENABLED: 'true') { example.run }
  ensure
    GlobalConfig.clear_cache(nicho::PADRAO_KEY)
  end

  def admin_de(account)
    create(:user, account: account, role: :administrator)
  end

  def frases(account, template:, total:, atender: false)
    get "/api/v1/accounts/#{account.id}/crm/stage_criteria/defaults",
        params: { names: Array.new(total) { |i| "Etapa #{i + 1}" }, atender: atender, template: template,
                  positions: (1..total).map(&:to_s) },
        headers: auth_headers(admin_de(account))
    expect(response).to have_http_status(:ok)
    response.parsed_body['payload'].pluck('criteria')
  end

  def base(chave)
    I18n.t("crm.stage_criteria.#{chave}", locale: :pt_BR)
  end

  def do_pacote(chave)
    Autonomia::Segmentos::Catalogo.dados.dig('seguros/saude_beneficios', :pt_BR, :crm, :stage_criteria, *chave.split('.').map(&:to_sym))
  end

  it 'saúde: a Venda de plano fala de vidas e de operadora; a conta geral segue com as frases de hoje' do
    saude_frases = frases(saude, template: 'VENDAS', total: 5)

    expect(saude_frases).to eq((1..5).map { |n| do_pacote("vendas.e#{n}") })
    expect(saude_frases[1]).to include('quantas vidas')
    expect(saude_frases[3]).to include('operadora')
    expect(frases(geral, template: 'VENDAS', total: 5)).to eq((1..5).map { |n| base("vendas.e#{n}") })
  end

  it 'Carteira é de Atender, por modelo e posição, com as quatro frases da base' do
    expect(frases(saude, template: 'CARTEIRA', total: 4, atender: true)).to eq((1..4).map { |n| base("carteira.e#{n}") })
    expect(frases(saude, template: 'CARTEIRA', total: 4)).to all(eq(''))
  end

  it 'cria o funil Carteira com o modelo e os nomes "Renovado" / "Cancelado"' do
    post "/api/v1/accounts/#{saude.id}/crm/pipelines",
         params: { pipeline: { name: 'Carteira', counts_as_sale: false, template: 'CARTEIRA',
                               outcome_labels: { success: 'Renovado', failure: 'Cancelado' } } },
         headers: auth_headers(admin_de(saude)), as: :json

    expect(response).to have_http_status(:created)
    pipeline = saude.crm_pipelines.find(response.parsed_body.dig('payload', 'id'))
    expect(pipeline.metadata).to include('template' => 'CARTEIRA',
                                         'outcome_labels' => { 'success' => 'Renovado', 'failure' => 'Cancelado' })
  end

  it 'o relatório baixado da saúde diz Implantado; o que não fechou segue a camada seguros' do
    statuses = Autonomia::Segmentos::Catalogo.dados.dig('seguros/saude_beneficios', :pt_BR, :crm, :export, :statuses)

    expect(statuses).to eq(won: 'Implantado')
    Autonomia::Segmentos::Pacotes.with(saude) do
      expect(I18n.t('crm.export.statuses.lost', locale: :pt_BR)).to eq('Não fechou')
    end
  end

  it 'a Carteira nasce sem lembrete de andamento nem de "deu certo?"; Suporte e Cobrança seguem como hoje' do
    carteira, = create_crm_pipeline(account: saude, user: admin_de(saude))
    carteira.update!(counts_as_sale: false, metadata: carteira.metadata.merge('template' => 'CARTEIRA'))
    suporte, = create_crm_pipeline(account: saude, user: admin_de(saude))
    suporte.update!(counts_as_sale: false, metadata: suporte.metadata.merge('template' => 'ATENDIMENTO'))

    expect(Crm::Ai::Config.service_reminders_settings(carteira)).to include('progress' => false, 'resolved_check' => false)
    expect(Crm::Ai::Config.service_reminders_settings(suporte)).to include('progress' => true, 'resolved_check' => true)
    cobranca, = create_crm_pipeline(account: saude, user: admin_de(saude))
    cobranca.update!(counts_as_sale: false, metadata: cobranca.metadata.merge('template' => 'COBRANCA'))
    expect(Crm::Ai::Config.service_reminders_settings(cobranca)).to include('progress' => false, 'resolved_check' => false, 'payment' => true)
  end

  it 'a variante da saúde dá andamento à E3 da Carteira; a conta geral não tem variante' do
    expect(Crm::PipelineStages::TemplateVariant.category_for(account: saude, template: 'CARTEIRA', position: 3)).to eq('andamento')
    expect(Crm::PipelineStages::TemplateVariant.category_for(account: geral, template: 'CARTEIRA', position: 3)).to be_nil
  end
end

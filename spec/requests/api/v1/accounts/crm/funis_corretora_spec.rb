require 'rails_helper'

# #1802: os funis da corretora. A "Venda de seguro" é o modelo VENDAS com a frase do corretor (pacote
# seguros/corretora); Renovação (Vender), Sinistro e Alteração na apólice (Atender) são modelos novos, com o critério
# no catálogo base. Conta geral fica com as frases de hoje.
RSpec.describe 'CRM funis da corretora (#1802)', type: :request do
  let(:nicho) { Autonomia::Agents::Nicho }
  let(:corretora) { create(:account, locale: 'pt_BR', internal_attributes: { nicho::NICHO_KEY => 'seguros', nicho::PERFIL_KEY => 'corretora' }) }
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

  it 'corretora: a Venda de seguro fala de cotação; a conta geral segue com as frases de hoje' do
    corretora_frases = frases(corretora, template: 'VENDAS', total: 5)
    geral_frases = frases(geral, template: 'VENDAS', total: 5)

    expect(corretora_frases[1]).to include('a equipe disse que está cotando')
    expect(corretora_frases).to all(be_present)
    expect(geral_frases).to eq((1..5).map { |n| base("vendas.e#{n}") })
  end

  it 'Renovação é de Vender e traz as cinco frases da base, para qualquer conta' do
    expect(frases(corretora, template: 'RENOVACAO', total: 5)).to eq((1..5).map { |n| base("renovacao.e#{n}") })
    expect(frases(corretora, template: 'RENOVACAO', total: 5, atender: true)).to all(eq(''))
  end

  it 'Sinistro e Alteração na apólice são de Atender, por modelo e posição' do
    expect(frases(corretora, template: 'SINISTRO', total: 4, atender: true)).to eq((1..4).map { |n| base("sinistro.e#{n}") })
    expect(frases(corretora, template: 'ALTERACAO', total: 4, atender: true)).to eq((1..4).map { |n| base("alteracao.e#{n}") })
    expect(frases(corretora, template: 'SINISTRO', total: 4)).to all(eq(''))
  end

  it 'cria o funil Renovação com o modelo e os nomes "Renovou" / "Não renovou"' do
    post "/api/v1/accounts/#{corretora.id}/crm/pipelines",
         params: { pipeline: { name: 'Renovação', counts_as_sale: true, template: 'RENOVACAO',
                               outcome_labels: { success: 'Renovou', failure: 'Não renovou' } } },
         headers: auth_headers(admin_de(corretora)), as: :json

    expect(response).to have_http_status(:created)
    pipeline = corretora.crm_pipelines.find(response.parsed_body.dig('payload', 'id'))
    expect(pipeline.metadata).to include('template' => 'RENOVACAO',
                                         'outcome_labels' => { 'success' => 'Renovou', 'failure' => 'Não renovou' })
  end

  # Revisão do Multifunnel: a etapa criada pelo stages_controller (apply_default_ai_criteria!) grava a frase do pacote
  # da conta, pelo modelo e posição (Vendas) e pelo nome (funil antigo, by_name com locale explícito pt_BR).
  describe 'etapa criada pela API' do
    def criar_etapa(account, stage, template: nil)
      user = admin_de(account)
      pipeline, = create_crm_pipeline(account: account, user: user)
      pipeline.update!(metadata: pipeline.metadata.merge('template' => template)) if template
      post "/api/v1/accounts/#{account.id}/crm/pipelines/#{pipeline.id}/stages",
           params: { stage: stage }, headers: auth_headers(user), as: :json
      expect(response).to have_http_status(:created)
      account.crm_pipeline_stages.find(response.parsed_body.dig('payload', 'id')).metadata['ai_criteria']
    end

    def do_pacote(chave, locale = :pt_BR)
      Autonomia::Segmentos::Catalogo.dados.dig('seguros/corretora', locale, :crm, :stage_criteria, *chave.split('.').map(&:to_sym))
    end

    it 'corretora: a etapa do Vendas grava a frase de corretor; a conta geral grava a de hoje' do
      etapa = { name: 'Cotando', template_position: 2 }

      expect(criar_etapa(corretora, etapa, template: 'VENDAS')).to eq(do_pacote('vendas.e2'))
      expect(do_pacote('vendas.e2')).to include('a equipe disse que está cotando')
      expect(criar_etapa(geral, etapa, template: 'VENDAS')).to eq(base('vendas.e2'))
    end

    it 'corretora: "Em atendimento" de funil antigo (pelo nome, locale explícito) grava o legado do pacote' do
      etapa = { name: 'Em atendimento' }

      expect(criar_etapa(corretora, etapa)).to eq(do_pacote('legado.em_atendimento'))
      expect(do_pacote('legado.em_atendimento')).to include('CEP de pernoite')
      expect(criar_etapa(geral, etapa)).to eq(base('legado.em_atendimento'))
    end

    it 'corretora em inglês: o nome em português continua achando o legado do pacote em pt_BR' do
      corretora.update!(locale: 'en')

      expect(criar_etapa(corretora, { name: 'Em atendimento' })).to eq(do_pacote('legado.em_atendimento'))
    end
  end

  it 'defaults pelo nome (funil antigo): corretora recebe o legado do pacote; a geral, o de hoje' do
    pedir = lambda do |account|
      get "/api/v1/accounts/#{account.id}/crm/stage_criteria/defaults",
          params: { names: ['Em atendimento', 'Proposta', 'Perdido'] }, headers: auth_headers(admin_de(account))
      expect(response).to have_http_status(:ok)
      response.parsed_body['payload'].pluck('criteria')
    end
    seguros_perdido = Autonomia::Segmentos::Catalogo.dados.dig('seguros', :pt_BR, :crm, :stage_criteria, :legado, :perdido)
    legado = Autonomia::Segmentos::Catalogo.dados.dig('seguros/corretora', :pt_BR, :crm, :stage_criteria, :legado)

    expect(pedir.call(corretora)).to eq([legado[:em_atendimento], legado[:proposta], seguros_perdido])
    expect(pedir.call(geral)).to eq(%w[em_atendimento proposta perdido].map { |k| base("legado.#{k}") })
  end
end

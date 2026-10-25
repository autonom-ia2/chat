require 'rails_helper'

# Relatório baixado de Anúncios (#1960): a planilha traz os mesmos números da tela, em quatro abas.
RSpec.describe Crm::MetaAds::Relatorio::Planilha do
  let(:account) { create(:account, name: 'Loja Exemplo') }
  let(:pipeline) { create_crm_pipeline(account: account, user: create(:user, account: account)).first }
  let(:stage) { account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Novo', position: 1) }
  let(:auto) { '120254710362980416' }
  let(:now) { Time.zone.parse('2026-10-20T15:00:00-03:00') }

  def from_ad(name, at, status: nil, value: 0)
    conversation = create(:conversation, account: account, contact: create(:contact, account: account, name: name))
    click = { 'source' => 'meta_ctwa', 'source_id' => auto, 'source_type' => 'ad', 'headline' => 'Seguro auto sem complicação',
              'touched_at' => at.utc.iso8601 }
    conversation.update_columns(additional_attributes: { 'campaign' => click, 'campaign_touches' => [click] }) # rubocop:disable Rails/SkipsModelValidations
    if status
      Crm::Card.create!(account: account, pipeline: pipeline, stage: stage, title: name, currency: 'BRL', primary_conversation: conversation,
                        status: status, value_cents: (value * 100).to_i)
    end
    conversation
  end

  # Escreveu e ninguém respondeu: sai como "Sem resposta".
  def esperando(name, at)
    conversation = from_ad(name, at)
    conversation.messages.create!(account: account, inbox: conversation.inbox, message_type: :incoming, content: 'Oi', created_at: at)
    conversation
  end

  def dados
    Crm::MetaAds::Relatorio::Dados.new(nil, period: '30d', account: account)
  end

  around do |example|
    I18n.with_locale(:pt_BR) { travel_to(now) { example.run } }
  end

  it 'traz o resumo, os anúncios, as conversas e os dias do período' do
    from_ad('Paulo Lima', 2.days.ago, status: :won, value: 950)
    esperando('Joana Dias', 1.day.ago)

    planilha = Roo::Excelx.new(StringIO.new(described_class.new(dados).gerar))
    linhas = ->(aba) { (1..planilha.sheet(aba).last_row).map { |linha| planilha.sheet(aba).row(linha) } }

    expect(planilha.sheets).to eq(['Resumo', 'Anúncios', 'Conversas', 'Por dia'])
    expect(linhas.call(0)).to include(['Conversas que vieram de anúncio', 2], ['Vendas', 1], ['Valor vendido', 950])
    expect(linhas.call(1).flatten).to include('Seguro auto sem complicação')
    expect(linhas.call(2).flatten).to include('Paulo Lima', 'Comprou', 'Joana Dias', 'Sem resposta')
    expect(linhas.call(3).size).to eq(Relatorios::Planilha::HEADER_ROW + 30) # um dia por linha, 30 dias contando hoje
  end

  # #2075: sem `sales_value_view`, nada de valor: nem a linha do resumo, nem a coluna (vazia ou "R$ 0").
  it 'sem os valores de venda, tira o valor vendido do resumo e a coluna de valor dos anúncios e das conversas' do
    from_ad('Paulo Lima', 2.days.ago, status: :won, value: 950)
    olhar = instance_double(Crm::MetaAds::VisibleConversations, sales_values?: false, card_value?: false)
    allow(olhar).to receive(:ids) { |ids| Set.new(ids) }

    dados = Crm::MetaAds::Relatorio::Dados.new(nil, period: '30d', account: account, visible: olhar)
    planilha = Roo::Excelx.new(StringIO.new(described_class.new(dados).gerar))
    celulas = (0..3).flat_map { |aba| (1..planilha.sheet(aba).last_row).flat_map { |linha| planilha.sheet(aba).row(linha) } }

    expect(celulas).to include('Vendas', 'Paulo Lima', 'Comprou')
    expect(celulas).not_to include('Valor vendido', 'Valor', 950)
  end

  it 'com conexão, o gasto dos anúncios que levam ao site sai numa linha própria, fora do investido (#2054)' do
    connection = create_meta_ads_insights_connection(account)
    Crm::MetaAdObject.create!(account: account, meta_object_id: 'set-site', object_type: 'adset', destination_type: 'WEBSITE', fetched_at: now)
    [[auto, 100, nil], ['120254932730050416', 40, 'set-site']].each do |ad_id, value, adset_id|
      Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: connection.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 19),
                                      adset_id: adset_id, currency: 'BRL', spend: value, attribution_window: '7d_click', fetched_at: now)
    end
    conversation = from_ad('Paulo Lima', 1.day.ago)
    Crm::MetaAdLink.create!(account: account, conversation: conversation, touch_key: 'k1', origin: 'whatsapp', certainty: 'ad', ad_id: auto,
                            touched_at: 1.day.ago)

    dados = Crm::MetaAds::Relatorio::Dados.new(connection, account: account, period: '30d')
    planilha = Roo::Excelx.new(StringIO.new(described_class.new(dados).gerar))
    resumo = (1..planilha.sheet(0).last_row).map { |linha| planilha.sheet(0).row(linha) }

    expect(resumo).to include(['Investido', 100], ['Outros anúncios (sem conversa)', 40])
  end
end

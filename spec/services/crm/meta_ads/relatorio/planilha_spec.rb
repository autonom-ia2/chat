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
    Crm::MetaAds::Relatorio::Dados.new(nil, days: 30, account: account)
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
end

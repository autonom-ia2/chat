require 'rails_helper'

# O "Ver" de Números › "De onde vieram os clientes" (#2001, F6): a Lista com `entrou_em` + `origem` ou `anuncio` mostra
# exatamente os cards que a tela conta (mesma seleção e mesma origem), e sem o mês a origem é ignorada.
RSpec.describe Crm::Cards::FilterQuery do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let!(:do_anuncio) { card(campaign: { 'source' => 'meta_ctwa', 'source_id' => anuncio }) }
  let!(:fechou_agora) do
    card(campaign: { 'source' => 'meta_ctwa', 'source_id' => anuncio }, criado: Time.utc(2026, 9, 2, 12), ganho_em: Time.utc(2026, 10, 3, 12))
  end
  let!(:direto) { card }
  let!(:mes_passado) { card(campaign: { 'source' => 'meta_ctwa', 'source_id' => anuncio }, criado: Time.utc(2026, 9, 2, 12)) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:visibility) do
    Crm::Conversations::Visibility.new(account: account, user: admin, account_user: admin.account_users.find_by!(account: account))
  end
  let(:anuncio) { '120210000000101' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { travel_to(Time.utc(2026, 10, 20, 15, 0)) { example.run } }
  end

  def card(campaign: nil, criado: Time.utc(2026, 10, 5, 12), ganho_em: nil)
    pipeline, stage = vendas
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    conversation.update_columns(additional_attributes: { 'campaign' => campaign }) if campaign # rubocop:disable Rails/SkipsModelValidations
    card = account.crm_cards.create!(pipeline: pipeline, stage: stage, primary_conversation: conversation, title: SecureRandom.hex(3),
                                     created_at: criado)
    card.update_columns(status: Crm::Card.statuses[:won], closed_at: ganho_em) if ganho_em # rubocop:disable Rails/SkipsModelValidations
    card
  end

  def lista(params)
    described_class.new(scope: account.crm_cards, params: params.merge(pipeline_id: vendas.first.id), conversation_visibility: visibility,
                        account: account)
                   .perform.to_a
  end

  it 'mostra quem entrou ou fechou no mês, de cada origem, com o tamanho que a tela diz' do
    tela = Crm::Numeros::Origens::Tela.new(
      account: account, mes: Crm::Numeros::Mes.new(account: account, chave: '2026-10'),
      funis: Crm::Numeros::Origens::Funis.new(account: account, acesso: Crm::Access::VisiblePipelines.new(user: admin, account: account)),
      perfil: { gasto: false, valor: true }
    ).perform

    expect(lista(entrou_em: '2026-10')).to contain_exactly(do_anuncio, fechou_agora, direto)
    expect(lista(entrou_em: '2026-10', origem: 'anuncio_meta')).to contain_exactly(do_anuncio, fechou_agora)
    expect(tela[:origens].find { |linha| linha[:tipo] == 'anuncio_meta' }[:lista]).to eq(2)
    expect(lista(entrou_em: '2026-10', origem: 'direto')).to contain_exactly(direto)
    expect(lista(entrou_em: '2026-10', anuncio: anuncio)).to contain_exactly(do_anuncio, fechou_agora)
    expect(tela[:anuncios].first[:lista]).to eq(2)
  end

  it 'link quebrado (origem sem mês, mês inválido ou fora do limite) mostra a lista vazia, nunca o funil inteiro' do
    expect(lista({})).to contain_exactly(do_anuncio, fechou_agora, direto, mes_passado)
    expect(lista(origem: 'direto')).to be_empty
    expect(lista(entrou_em: '2026-13', origem: 'direto')).to be_empty
    expect(lista(entrou_em: '2024-01')).to be_empty
  end
end

require 'rails_helper'

# Números › "De onde vieram os clientes" (#2001, F6): os números da tela batem com as regras do "Como contamos" — em
# "Todos os funis" e num funil —, a origem é a do primeiro toque, a venda conta no mês em que fechou, e o gasto e o R$
# seguem quem vê o quê.
RSpec.describe Crm::Numeros::Origens::Tela do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_inbox(account: account) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas').tap { |(funil, _)| funil.update!(is_default: true) } }
  let(:suporte) { create_crm_pipeline(account: account, user: admin, name: 'Suporte').tap { |(funil, _)| funil.update!(counts_as_sale: false) } }
  let(:acesso) { Crm::Access::VisiblePipelines.new(user: admin, account: account) }
  let(:anuncio) { '120210000000101' }

  around do |example|
    with_modified_env('CRM_KANBAN_ENABLED' => 'true') { travel_to(Time.utc(2026, 10, 20, 15, 0)) { example.run } }
  end

  def toque(source, **extra)
    { 'source' => source, 'source_id' => extra.delete(:source_id), 'headline' => extra.delete(:headline) }.compact.merge(extra)
  end

  def card(funil:, criado: Time.utc(2026, 10, 5, 12), campaign: nil, valor: 0, **attrs)
    pipeline, stage = funil
    conversation = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    conversation.update_columns(additional_attributes: { 'campaign' => campaign }) if campaign # rubocop:disable Rails/SkipsModelValidations
    account.crm_cards.create!(pipeline: pipeline, stage: stage, primary_conversation: conversation, contact: conversation.contact,
                              title: "Card #{SecureRandom.hex(3)}",
                              value_cents: valor, created_at: criado, **attrs)
  end

  def ganho(card, quando: Time.utc(2026, 10, 10, 12))
    card.update_columns(status: Crm::Card.statuses[:won], closed_at: quando) # rubocop:disable Rails/SkipsModelValidations
    card
  end

  def tela(funil: nil, gasto: true, valor: true, mes: nil)
    funis = Crm::Numeros::Origens::Funis.new(account: account, acesso: acesso, pedido: funil)
    described_class.new(account: account, mes: Crm::Numeros::Mes.new(account: account, chave: mes), funis: funis,
                        perfil: { gasto: gasto, valor: valor }).perform
  end

  def origem(payload, tipo)
    payload[:origens].find { |linha| linha[:tipo] == tipo }
  end

  describe 'as origens' do
    before do
      ganho(card(funil: vendas, campaign: toque('meta_ctwa', source_id: anuncio, headline: 'Oferta'), valor: 150_000))
      card(funil: vendas, campaign: toque('meta_ctwa', source_id: anuncio))
      card(funil: vendas, campaign: toque('google_ads'))
      card(funil: vendas, campaign: toque('tracked_link'))
      card(funil: vendas)
      card(funil: vendas, campaign: toque('meta_organic'))
      # Toque antigo, gravado antes do campo `source`: a origem sai da regra do próprio toque (clique de anúncio).
      card(funil: vendas, campaign: { 'source_type' => 'ad', 'source_id' => anuncio })
      card(funil: suporte, campaign: toque('meta_ctwa', source_id: anuncio))
      card(funil: suporte)
      # Fora do mês: não conta.
      card(funil: vendas, criado: Time.utc(2026, 9, 10, 12), campaign: toque('google_ads'))
    end

    it 'conta o funil principal por padrão, com cada origem, e "outros caminhos" por último' do
      payload = tela

      expect(payload[:funil]).to include(escolhido: vendas.first.id.to_s, nome: 'Vendas')
      expect(payload[:origens].map { |linha| linha[:tipo] }).to eq(%w[anuncio_meta direto google site outras])
      expect(origem(payload, 'anuncio_meta')).to eq(tipo: 'anuncio_meta', clientes: 3, vendas: 1, valor: 1500.0, lista: 3)
      expect(origem(payload, 'direto')).to include(clientes: 1, vendas: 0, lista: 1)
      expect(payload[:anuncios]).to contain_exactly(include(id: anuncio, titulo: 'Oferta', clientes: 3, vendas: 1, valor: 1500.0))
    end

    it 'em "Todos os funis" soma os funis linha a linha' do
      payload = tela(funil: 'todos')

      expect(payload[:funil][:escolhido]).to eq('todos')
      expect(payload[:funil][:opcoes].pluck(:id)).to eq([vendas.first.id.to_s, suporte.first.id.to_s, 'todos'])
      expect(origem(payload, 'anuncio_meta')).to include(clientes: 4, vendas: 1)
      expect(origem(payload, 'direto')).to include(clientes: 2)
      expect(payload[:origens].sum { |linha| linha[:clientes] }).to eq(9)
    end

    it 'num funil sem venda, só as contagens' do
      payload = tela(funil: suporte.first.id.to_s)

      expect(payload[:origens].sum { |linha| linha[:clientes] }).to eq(2)
      expect(payload[:origens].sum { |linha| linha[:vendas] }).to eq(0)
    end

    it 'esconde o R$ de quem não vê os valores de venda, e mantém as contagens' do
      payload = tela(valor: false)

      expect(payload[:valorOculto]).to be(true)
      expect(origem(payload, 'anuncio_meta')).to include(vendas: 1, valor: nil)
      expect(payload[:anuncios].first[:valor]).to be_nil
    end
  end

  it 'conta a venda no mês em que fechou, e a lista leva quem entrou ou fechou' do
    ganho(card(funil: vendas, criado: Time.utc(2026, 9, 3, 12), campaign: toque('google_ads'), valor: 90_000))
    card(funil: vendas, campaign: toque('google_ads'))

    expect(origem(tela, 'google')).to eq(tipo: 'google', clientes: 1, vendas: 1, valor: 900.0, lista: 2)
    expect(origem(tela(mes: '2026-09'), 'google')).to include(clientes: 1, vendas: 0)
  end

  it 'a origem é a do primeiro toque entre as conversas do card' do
    primeiro = card(funil: vendas, campaign: toque('google_ads', touched_at: '2026-10-01T10:00:00Z'))
    depois = create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account))
    depois.update_columns(additional_attributes: { 'campaign' => toque('meta_ctwa', source_id: anuncio, touched_at: '2026-10-04T10:00:00Z') }) # rubocop:disable Rails/SkipsModelValidations
    Crm::CardConversation.create!(account: account, card: primeiro, conversation: depois)

    expect(tela[:origens].map { |linha| linha[:tipo] }).to eq(%w[google])
  end

  # #2232: a primeira conversa vem da principal ou das ligadas, pelo mesmo desempate (sem data primeiro, depois a mais
  # antiga, depois o menor id), e a principal ligada de novo não muda nada.
  it 'escolhe o primeiro toque entre a principal e as ligadas, com o toque sem data na frente' do
    ligar = lambda do |alvo, campaign|
      conversa = create_crm_conversation(account: account, inbox: inbox, contact: alvo.contact)
      conversa.update_columns(additional_attributes: { 'campaign' => campaign }) # rubocop:disable Rails/SkipsModelValidations
      Crm::CardConversation.create!(account: account, card: alvo, conversation: conversa)
    end
    ligada_antes = card(funil: vendas, campaign: toque('google_ads', touched_at: '2026-10-04T10:00:00Z'))
    ligar.call(ligada_antes, toque('meta_ctwa', source_id: anuncio, touched_at: '2026-10-01T10:00:00Z'))
    sem_data = card(funil: vendas, campaign: toque('google_ads', touched_at: '2026-10-01T10:00:00Z'))
    ligar.call(sem_data, toque('tracked_link'))
    principal_ligada = card(funil: vendas, campaign: toque('google_ads', touched_at: '2026-10-02T10:00:00Z'))
    Crm::CardConversation.create!(account: account, card: principal_ligada, conversation: principal_ligada.primary_conversation)
    ligar.call(principal_ligada, toque('meta_organic', touched_at: '2026-10-03T10:00:00Z'))

    linhas = Crm::Numeros::Origens::Classificador.new(account.crm_cards, Crm::Numeros::Mes.new(account: account, chave: nil).range).linhas

    expect(linhas.to_h { |linha| [linha.id, [linha.tipo, linha.ad_id]] }).to eq(
      ligada_antes.id => ['anuncio_meta', anuncio], sem_data.id => ['site', nil], principal_ligada.id => ['google', nil]
    )
  end

  # #2084/#2085: contato parceiro do mercado ou "não é negócio" sai dos Números pela regra única (Crm::Relacao), com a flag.
  it 'tira o contato marcado como parceiro ou "não é negócio" com a flag contato_relacao, e card sem contato conta' do
    parceiro = card(funil: vendas, campaign: toque('google_ads'))
    parceiro.contact.update!(relacao: :parceiro)
    card(funil: vendas, campaign: toque('google_ads')).contact.update!(relacao: :nao_e_negocio)
    card(funil: vendas, campaign: toque('google_ads'))
    sem_contato = card(funil: vendas)
    sem_contato.update_columns(contact_id: nil) # rubocop:disable Rails/SkipsModelValidations

    expect(origem(tela, 'google')[:clientes]).to eq(3)

    account.enable_features!('contato_relacao')

    expect(origem(tela, 'google')[:clientes]).to eq(1)
    expect(origem(tela, 'direto')[:clientes]).to eq(1)
  end

  it 'mês sem ninguém: vazio, com o seletor de funil' do
    vendas

    expect(tela).to include(vazio: true, origens: [], gasto: nil)
    expect(tela[:funil][:opcoes]).to be_present
  end

  describe 'o gasto com anúncios' do
    let!(:conexao) { create_meta_ads_insights_connection(account) }

    before do
      ganho(card(funil: vendas, campaign: toque('meta_ctwa', source_id: anuncio), valor: 100_000))
      card(funil: vendas, campaign: toque('meta_ctwa', source_id: anuncio))
      card(funil: suporte, campaign: toque('meta_ctwa', source_id: anuncio))
      [[anuncio, 300, 40], ['999999999', 100, 10]].each do |ad_id, gasto, cliques|
        Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: conexao.ad_account_id, ad_id: ad_id, date: Date.new(2026, 10, 6),
                                        currency: 'BRL', spend: gasto, link_clicks: cliques, attribution_window: '7d_click',
                                        fetched_at: Time.current)
      end
      # Mês passado: fica fora.
      Crm::MetaAdInsightDaily.create!(account: account, ad_account_id: conexao.ad_account_id, ad_id: anuncio, date: Date.new(2026, 9, 6),
                                      currency: 'BRL', spend: 999, attribution_window: '7d_click', fetched_at: Time.current)
    end

    it 'aparece só em "Todos os funis", com os clientes de anúncio de todos os funis' do
      payload = tela(funil: 'todos')

      expect(payload[:gasto]).to eq(total: 400.0, porCliente: 133.33, porVenda: 400.0, retorno: 2.5, toques: 50, clientes: 3)
      expect(payload[:anuncios].first).to include(id: anuncio, gasto: 300.0, porVenda: 300.0)
      expect(payload).to include(gastoOculto: false, gastoEmTodos: false)
    end

    it 'com um funil escolhido, nada de gasto na tela e o convite para "Todos os funis"' do
      payload = tela

      expect(payload[:gasto]).to be_nil
      expect(payload[:gastoEmTodos]).to be(true)
      expect(payload[:anuncios].first).not_to include(:gasto, :porVenda)
    end

    it 'sem a permissão de anúncios, nenhum número de gasto, só o aviso' do
      payload = tela(funil: 'todos', gasto: false)

      expect(payload[:gasto]).to be_nil
      expect(payload[:gastoOculto]).to be(true)
      expect(payload[:anuncios].first).not_to include(:gasto, :porVenda)
      expect(tela(gasto: false)[:gastoEmTodos]).to be(false)
    end

    it 'sem o R$ de venda, o retorno some (é tirado do dinheiro)' do
      expect(tela(funil: 'todos', valor: false)[:gasto]).to include(retorno: nil, total: 400.0)
    end

    it 'gasto em outra moeda que a das vendas: nada de gasto, custo nem retorno' do
      Crm::MetaAdInsightDaily.where(account_id: account.id).update_all(currency: 'USD') # rubocop:disable Rails/SkipsModelValidations

      expect(tela(funil: 'todos')).to include(gasto: nil, gastoOculto: false)
      expect(tela[:gastoEmTodos]).to be(false)
    end

    it 'conexão parada: nada de gasto nem aviso' do
      conexao.update!(status: 'invalid')

      expect(tela(funil: 'todos')).to include(gasto: nil, gastoOculto: false)
      expect(tela(funil: 'todos', gasto: false)).to include(gastoOculto: false)
    end
  end
end

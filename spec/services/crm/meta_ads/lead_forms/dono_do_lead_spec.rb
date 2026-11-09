require 'rails_helper'

# G30 (#2702): o card do lead do formulário nasce com o dono que a Atribuição do funil daria. O card não tem conversa nem
# caixa: quem pode receber é quem cuida do funil nas caixas ligadas a ele (Crm::Entrega::QuemCuida). Funil sem
# Atribuição ligada, ou sem ninguém que possa receber, fica como hoje: sem dono.
RSpec.describe Crm::MetaAds::LeadForms::DonoDoLead do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Dona') }
  let(:ana) { create(:user, account: account, role: :agent, name: 'Ana Corretora') }
  let(:bruno) { create(:user, account: account, role: :agent, name: 'Bruno Corretor') }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:caixa) { create_crm_whatsapp_api_inbox(account: account, members: [ana, bruno]) }

  def lead(id, telefone)
    { 'id' => id, 'created_time' => '2026-11-08T12:00:00+0000', 'form_id' => '9001', 'ad_name' => 'Apartamento Jardim',
      'field_data' => [{ 'name' => 'full_name', 'values' => ["Lead #{id}"] }, { 'name' => 'phone_number', 'values' => [telefone] }] }
  end

  def atribuicao(**regra)
    funil.update!(metadata: { 'ai' => { 'handoff' => { 'enabled' => true }.merge(regra.stringify_keys) } })
  end

  def online(*pessoas)
    allow(OnlineStatusTracker).to receive(:get_available_users).and_return(pessoas.to_h { |pessoa| [pessoa.id.to_s, 'online'] })
  end

  # Um importer por lead, como o webhook (FacebookLeadgenJob): cada um lê a regra e a fila de novo.
  def dono_do_lead(id, telefone)
    Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: etapa, form_name: 'Visitas').import(lead(id, telefone))
    Crm::MetaAdsLead.find_by(leadgen_id: id).card.owner
  end

  before do
    account.crm_pipeline_inboxes.create!(pipeline: funil, inbox: caixa)
    online
  end

  it 'com a Atribuição ligada, o lead vai para quem cuida do funil com menos cards abertos nele', :aggregate_failures do
    atribuicao
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Card da Ana', currency: 'BRL', owner: ana)

    expect(dono_do_lead('L1', '+5511987650001')).to eq(bruno)
    expect(dono_do_lead('L2', '+5511987650002')).to eq(ana)
  end

  it 'prefere quem está online, sem segurar o lead quando ninguém está' do
    atribuicao(prefer_online: true)
    online(ana)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Card da Ana', currency: 'BRL', owner: ana)

    expect(dono_do_lead('L1', '+5511987650001')).to eq(ana)
  end

  # Revisão da Meta aprovar: no "trazer quem já preencheu" (até 90 dias de leads), preferir online mandaria o lote inteiro
  # para quem estivesse online na hora. Em lote vale a fila inteira, e a fila é lida uma vez só.
  it 'em lote, divide pela fila inteira sem olhar quem está online e lê a fila uma vez', :aggregate_failures do
    atribuicao(prefer_online: true)
    online(ana)
    allow(Crm::Entrega::QuemCuida).to receive(:na_caixa).and_call_original
    em_lote = Crm::MetaAds::LeadForms::Importer.new(account: account, pipeline: funil, stage: etapa, form_name: 'Visitas', em_lote: true)

    %w[L1 L2 L3 L4].each_with_index { |id, indice| em_lote.import(lead(id, "+551198765000#{indice}")) }

    expect(account.crm_cards.group(:owner_id).count).to eq({ ana.id => 2, bruno.id => 2 })
    expect(Crm::Entrega::QuemCuida).to have_received(:na_caixa).once
  end

  # Dois FacebookLeadgenJob do mesmo funil em paralelo leriam a contagem antes do commit um do outro e cairiam na mesma
  # pessoa: a fila trava por funil antes de contar, até o fim da transação que grava o card.
  it 'trava a fila do funil antes de contar os cards, e só dentro de transação', :aggregate_failures do
    atribuicao
    conexao = Crm::Card.connection
    allow(conexao).to receive(:execute).and_call_original

    expect(dono_do_lead('L1', '+5511987650001')).to eq(ana)
    expect(conexao).to have_received(:execute)
      .with(a_string_including('pg_advisory_xact_lock', "crm_dono_do_lead:#{account.id}:#{funil.id}")).once

    allow(conexao).to receive(:transaction_open?).and_return(false)
    expect { described_class.new(pipeline: funil, stage: etapa).pessoa }.to raise_error(described_class::SemTransacao)
  end

  it 'a regra com pessoa fixa dá o lead a ela; fora de quem cuida do funil, vale a fila', :aggregate_failures do
    atribuicao(pool_type: 'user', pool_id: ana.id)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Card da Ana', currency: 'BRL', owner: ana)
    expect(dono_do_lead('L1', '+5511987650001')).to eq(ana)

    atribuicao(pool_type: 'user', pool_id: create(:user, account: account, role: :agent).id)
    expect(dono_do_lead('L2', '+5511987650002')).to eq(bruno)
  end

  it 'a regra da etapa vence a do funil' do
    atribuicao
    etapa.update!(metadata: { 'ai_handoff' => { 'pool_type' => 'user', 'pool_id' => ana.id } })
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Card da Ana', currency: 'BRL', owner: ana)

    expect(dono_do_lead('L1', '+5511987650001')).to eq(ana)
  end

  # Parecer da Funções: quem tem função sem `crm_view` não abre o card (CardPolicy#index? do EE). Dono que não abre o
  # card prende o lead: ninguém mais o pega.
  it 'quem tem função sem ver o CRM fica fora da fila, inclusive como pessoa fixa', :aggregate_failures do
    sem_crm = create(:custom_role, account: account, permissions: %w[conversation_manage])
    AccountUser.find_by(account: account, user: bruno).update!(custom_role: sem_crm)
    account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Card da Ana', currency: 'BRL', owner: ana)

    atribuicao(pool_type: 'user', pool_id: bruno.id)
    expect(dono_do_lead('L1', '+5511987650001')).to eq(ana)

    AccountUser.find_by(account: account, user: ana).update!(custom_role: sem_crm)
    expect(dono_do_lead('L2', '+5511987650002')).to be_nil
  end

  it 'sem a Atribuição ligada, ou sem ninguém que cuide do funil, o lead fica sem dono como hoje', :aggregate_failures do
    expect(dono_do_lead('L1', '+5511987650001')).to be_nil

    atribuicao
    caixa.inbox_members.destroy_all
    expect(dono_do_lead('L2', '+5511987650002')).to be_nil
  end
end

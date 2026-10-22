require 'rails_helper'

RSpec.describe Crm::Numeros::SoEu do
  let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:carla) { create(:user, account: account, role: :agent, name: 'Carla') }
  let(:inbox) { create_crm_inbox(account: account, members: [carla]) }
  let(:sale) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:service) do
    pipeline = account.crm_pipelines.create!(name: 'Suporte', created_by: admin, status: :active, counts_as_sale: false)
    [pipeline, account.crm_pipeline_stages.create!(pipeline: pipeline, name: 'Aberto', position: 0)]
  end

  around { |example| travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run } }

  def so_eu(user = carla, chave: nil, valor_da_equipe: true)
    acesso = Crm::Access::VisiblePipelines.new(user: user, account: account)
    described_class.new(account: account, user: user, mes: Crm::Numeros::Mes.new(account: account, chave: chave),
                        acesso: acesso, valor_da_equipe: valor_da_equipe).perform
  end

  def card(pipeline_and_stage, owner: carla, conversation: nil, **attrs)
    pipeline, stage = pipeline_and_stage
    account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, primary_conversation: conversation,
                              title: "Card #{SecureRandom.hex(3)}", **attrs)
  end

  def close(card, result = 'won')
    Crm::Cards::Closer.new(card: card, actor: admin, result: result).perform
  end

  def conversation(assignee: carla)
    create_crm_conversation(account: account, inbox: inbox, contact: create(:contact, account: account), assignee: assignee)
  end

  it 'quem só atende: topo de resolvidos, bloco Atendendo e nenhum R$ nem barra da equipe' do
    close(card(service))
    card(service, next_follow_up_at: 2.hours.ago)
    conversation

    result = so_eu

    expect(result).to include(papel: 'atende', vendendo: nil, equipePct: nil)
    expect(result[:topo]).to include(medida: 'resolvidos', feito: 1, meta: nil, botao: { tipo: 'meus_lembretes', n: 1 })
    expect(result[:atendendo][:itens].map { |item| [item[:tipo], item[:n]] })
      .to eq([['resolvidos', 1], ['com_voce', 1], ['deu_certo', 0]])
  end

  it 'quem vende e atende: os dois blocos, a frase do atendimento no topo e sem "A IA te ajudou"' do
    close(card(sale, value_cents: 10_000))
    close(card(service))

    result = so_eu

    expect(result[:papel]).to eq('vende_atende')
    expect(result[:topo][:frase]).to eq(tipo: 'eu_vende_atende', resolvidos: 1, noPrazo: nil)
    expect(result[:vendendo]).to be_present
    expect(result[:atendendo]).to be_present
    expect(result[:iaAjudou]).to be_nil
  end

  it 'sem card nenhum, o papel vem dos funis que a pessoa enxerga' do
    service

    expect(so_eu[:papel]).to eq('atende')
  end

  it 'botão em cascata: sem atrasados, as paradas com o valor; sem paradas, os cards' do
    sale
    expect(so_eu[:topo][:botao]).to eq(tipo: 'meus_cards')

    card(sale, value_cents: 250_000).update!(entered_stage_at: 10.days.ago)
    expect(so_eu[:topo][:botao]).to eq(tipo: 'meus_parados', n: 1, valor: 2500.0)
  end

  it 'só dá link aos fechados quando a Lista mostra exatamente os cards creditados' do
    venda = card(sale, value_cents: 10_000)
    close(venda)
    expect(so_eu[:vendendo][:itens].first).to include(tipo: 'fechadas', n: 1, lista: true)

    venda.update!(owner: admin)
    expect(so_eu[:vendendo][:itens].first).to include(n: 1, lista: false)
    expect(so_eu(chave: '2026-09')[:vendendo][:itens].first).to include(lista: false)
  end

  it '"A IA te ajudou": a passagem da IA no mês e a venda que veio dela, com o nome quando é uma IA só' do
    chat = conversation
    Crm::Passagem.create!(account: account, conversation: chat, de_type: 'AgentBot', de_id: 1, de_nome: 'Sofia',
                          para_type: 'User', para_id: carla.id, para_nome: 'Carla', em: 2.days.ago)
    close(card(sale, conversation: chat, value_cents: 5_000))

    expect(so_eu[:iaAjudou]).to eq(ia: 'Sofia', passou: 1, viraram: 1, tipo: 'venda')
  end

  it 'próximo passo: as pessoas da mesma campanha que estão com a pessoa, só no mês de hoje' do
    2.times do
      chat = conversation
      touch = { 'source_id' => 'campaign:whatsapp:7', 'source_type' => 'campaign_whatsapp', 'headline' => 'Dia das Crianças',
                'touched_at' => 3.days.ago.iso8601 }
      chat.update!(additional_attributes: { 'campaign_touches' => [touch] })
      card(sale, conversation: chat)
    end

    expect(so_eu[:proximo]).to eq([{ tipo: 'campanha_com_voce', n: 2, campanha: 'Dia das Crianças',
                                     origem: 'campaign:whatsapp:7' }])
    expect(so_eu(chave: '2026-09')[:proximo]).to eq([])
  end

  # #2075: sem `sales_value_view`, a pessoa segue vendo o próprio R$; só a barra da equipe (% da meta) some.
  it 'sem os valores de venda: o próprio R$ fica, a barra da equipe some' do
    sale.first.update!(metadata: { 'goals' => { 'monthly_target_cents' => 1_000_000, 'currency' => 'BRL' } })
    close(card(sale, value_cents: 250_000))

    expect(so_eu[:equipePct]).to eq(25)
    result = so_eu(valor_da_equipe: false)
    expect(result[:equipePct]).to be_nil
    expect(result[:topo]).to include(feito: 2500.0, fechadas: 1)
  end
end

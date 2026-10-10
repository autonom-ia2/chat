require 'rails_helper'

# Multifunil (#1146): a IA do card lê o que as ferramentas do agente produziram, para qualquer negócio.
RSpec.describe Crm::Ai::AgentResults do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:agent) do
    Autonomia::Agents::Agent.create!(account: account, name: 'Lia', agent_type: 'custom', status: :active, enabled: true,
                                     instruction: 'Atenda.')
  end
  let(:card) do
    pipeline, stage = create_crm_pipeline(account: account, user: admin)
    account.crm_cards.create!(pipeline: pipeline, stage: stage, title: 'Onix', primary_conversation: conversation)
  end
  let(:cotacao) { Autonomia::Agents::Tools::Native::InsuranceQuote }
  let(:handle_com_preco) do
    precos = { 'porto' => preco('Porto', 2100.5), 'allianz' => preco('Allianz', 1950),
               'hdi' => { 'nome' => 'HDI', 'desfecho' => 'sem_proposta' } }
    { 'produto' => 'auto', 'resultado_por_seguradora' => precos }
  end

  # opcoes: slug, handle, arguments, conversa.
  def run_de(status:, criado_em: Time.current, **opcoes)
    Autonomia::Agents::ToolRun.create!(
      account: account, agent: agent, conversation: opcoes.fetch(:conversa, conversation), slug: opcoes.fetch(:slug, cotacao.slug),
      status: status, faixa: 'auto:onix', execution_key: SecureRandom.uuid, arguments: opcoes.fetch(:arguments, {}),
      handle: opcoes.fetch(:handle, {}), created_at: criado_em, updated_at: criado_em
    )
  end

  def preco(nome, valor)
    { 'nome' => nome, 'desfecho' => 'com_preco', 'premio' => { 'amount' => valor, 'basis' => 'annual' } }
  end

  it 'resume a cotação terminada: o bem, o menor prêmio e quantas seguradoras cotaram' do
    card
    run_de(status: 'done', handle: handle_com_preco, arguments: { 'item' => 'Onix ABC1D23' }, criado_em: 1.minute.from_now)

    resultados = described_class.new(card: card).perform

    expect(resultados.size).to eq(1)
    expect(resultados.first[:tool]).to eq(cotacao.slug)
    expect(resultados.first[:summary]).to eq('Cotação de seguro auto — Onix ABC1D23: menor prêmio R$ 1.950,00 (Allianz); 2 seguradora(s) com preço.')
  end

  it 'deixa de fora o que veio antes do card, o que não terminou, a cotação sem preço e outra conversa' do
    run_de(status: 'done', handle: handle_com_preco, criado_em: 1.day.ago)
    card
    run_de(status: 'running', handle: handle_com_preco, criado_em: 1.minute.from_now)
    run_de(status: 'done', handle: { 'resultado_por_seguradora' => { 'hdi' => { 'nome' => 'HDI', 'desfecho' => 'sem_proposta' } } },
           criado_em: 2.minutes.from_now)
    run_de(status: 'done', handle: handle_com_preco, criado_em: 3.minutes.from_now,
           conversa: create(:conversation, account: account, inbox: inbox))

    expect(described_class.new(card: card).perform).to eq([])
  end

  it 'ferramenta sem resumo não entra' do
    card
    run_de(status: 'done', slug: 'ferramenta_que_nao_existe', criado_em: 1.minute.from_now)

    expect(described_class.new(card: card).perform).to eq([])
  end
end

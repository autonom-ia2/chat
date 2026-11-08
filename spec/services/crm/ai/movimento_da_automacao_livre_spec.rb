require 'rails_helper'

# #2428: o passo "ação" da Automação livre move o card pela porta da frente (ChamadaInterna, como quem ligou). Pega o
# movimento saindo como de pessoa, sem a marca da automação: o histórico dizia que a pessoa moveu e a IA do funil
# desfazia depois da janela, sem esperar mensagem nova do cliente.
RSpec.describe Crm::Ai::MovimentoDaAutomacao, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:proposta) { create_crm_stage(account: account, pipeline: funil_e_etapa.first, name: 'Proposta', position: 1) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: 'Pedido', currency: 'BRL',
                              primary_conversation: conversa, contact: conversa.contact)
  end
  let(:definicao) do
    automacao_ligada(account, admin, [{ 'id' => 'p1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move',
                                        'descricao' => 'Levar para Proposta', 'caminho' => { 'id' => card.id },
                                        'corpo' => { 'stage_id' => proposta.id } }])
  end

  before { ligar_motor(account) }

  after { Current.reset }

  def movimento = Crm::Activity.where(card: card, event_type: 'move').sole

  it 'o passo move o card, e o movimento leva a automação livre, com quem ligou como ator', :aggregate_failures do
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

    expect(card.reload.stage).to eq(proposta)
    expect(movimento.payload).to include('by' => 'automacao', 'origem' => 'livre', 'automacao_id' => definicao.id)
    expect(movimento).to have_attributes(actor_type: 'user', actor_id: admin.id)
  end

  it 'passada a janela, sem mensagem nova do cliente, a IA segue respeitando o movimento' do
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

    travel(Crm::Ai::Evaluator::RESPEITO_AO_MOVIMENTO + 1.hour) do
      expect(described_class.respeitar?(card.reload)).to be(true)
    end
  end

  it 'fora da cadeia (a pessoa movendo no quadro), o movimento não leva automação' do
    expect(Autonomia::Automacao::Cadeia.automacao_livre).to be_nil

    Autonomia::Automacao::Cadeia.restaurada(['regra:3']) do
      expect(Autonomia::Automacao::Cadeia.automacao_livre).to be_nil
    end
    Autonomia::Automacao::Cadeia.restaurada(['regra:3', "automacao:#{definicao.id}"]) do
      expect(Autonomia::Automacao::Cadeia.automacao_livre).to eq(origem: 'livre', id: definicao.id)
    end
  end
end

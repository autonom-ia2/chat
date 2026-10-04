require 'rails_helper'

# Ação em lote pelo Guia (#934): "move esses para Cotação".
#
# Os ids vêm no CORPO, não no caminho. Antes só o caminho era conferido, e um
# id chutado ao lado dos lidos passava calado (AC-CT5). E o lote precisa ter
# desfazer de verdade para o Guia poder fazê-lo sem clique (AC-CT6).
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Ação em lote do Guia' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:funil_e_etapa) { create_crm_pipeline(account: conta, user: admin) }
  let(:cotacao) { create_crm_stage(account: conta, pipeline: funil_e_etapa.first, name: 'Cotação') }
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }
  let(:agente) do
    Autonomia::Agents::Agent.create!(account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
                                     instruction: 'Guia.', config: { 'with_knowledge' => false })
  end
  let(:cards) { Array.new(2) { |i| card("Card #{i}") } }

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  def card(titulo)
    conta.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, title: titulo, currency: 'BRL')
  end

  def mover(ids)
    Autonomia::Agents::Tools::Native::GuiaExecucao.new(
      agent: agente, operador: operador,
      params: { 'acao' => 'POST crm/cards/bulk', 'descricao' => 'Movi os cards para Cotação.',
                'corpo_json' => { ids: ids, action_name: 'move', payload: { stage_id: cotacao.id } }.to_json }
    ).call
  end

  def ler_cards(ids)
    Autonomia::Guide::Tela.new(contexto: operador, tela: { 'rota' => 'crm_kanban_index',
                                                           'selecionados' => { 'recurso' => 'crm/cards', 'ids' => ids } }).bloco
  end

  # AC-CT5
  describe 'o corpo conferido' do
    it 'recusa o lote com um id que nenhuma leitura trouxe, e nada muda', :aggregate_failures do
      ler_cards(cards.map(&:id))

      resposta = mover([*cards.map(&:id), 99_999])

      expect(resposta).to include('Não executei', '99999')
      expect(cards.map { |item| item.reload.stage_id }.uniq).to eq([funil_e_etapa.last.id])
      expect(operador.execucao).to be_nil
    end

    it 'vale para qualquer rota com `*_ids` no corpo, também na proposta' do
      resposta = Autonomia::Agents::Tools::Native::GuiaAcao.new(
        agent: agente, operador: operador,
        params: { 'acao' => 'POST bulk_actions', 'descricao' => 'Resolver as conversas.',
                  'corpo_json' => { type: 'Conversation', ids: [123], fields: { status: 'resolved' } }.to_json }
      ).call

      expect(resposta).to include('Não preparei a ação', 'ids 123')
    end
  end

  # AC-CT6 — o lote passa pelos callbacks de cada card (`Crm::Cards::BulkAction` usa `update!` e o `Mover`),
  # então cai no caderno e volta inteiro com o desfazer. Por isso fica fora de `Acoes::SEM_DESFAZER`.
  describe 'o lote e o desfazer' do
    it 'move os cards lidos, anota cada um no caderno e desfaz', :aggregate_failures do
      ler_cards(cards.map(&:id))

      expect(mover(cards.map(&:id))).to start_with('Feito.')
      expect(cards.map { |item| item.reload.stage_id }).to eq([cotacao.id, cotacao.id])
      expect(operador.execucao.mudancas.where(record_type: 'Crm::Card').pluck(:record_id)).to match_array(cards.map(&:id))

      Autonomia::Guide::Desfazer.new(execucao: operador.execucao.reload, user: admin).perform

      expect(cards.map { |item| item.reload.stage_id }).to eq([funil_e_etapa.last.id] * 2)
      expect(operador.execucao.reload.pendencias).to be_empty
    end

    it 'não está entre as ações sem desfazer' do
      expect(operador.acoes.desfazivel?('POST crm/cards/bulk')).to be(true)
    end
  end
end
# rubocop:enable RSpec/DescribeClass

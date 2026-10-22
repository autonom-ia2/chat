require 'rails_helper'

# Arquivar não desfaz o fechamento: a venda arquivada continua nos Números, nas Metas e nos Relatórios, e reabrir o
# arquivado devolve o desfecho com a data de antes (Crm::Card::DESFECHO_ARQUIVADO).
RSpec.describe Crm::Card do
  describe 'arquivado depois de fechado' do
    let(:account) { create(:account, reporting_timezone: 'America/Sao_Paulo') }
    let(:ana) { create(:user, account: account, role: :administrator, name: 'Ana') }
    let(:sale) { create_crm_pipeline(account: account, user: ana) }
    let(:month) { Crm::Numeros::Mes.new(account: account) }
    let(:fechado_em) { Time.utc(2026, 10, 19, 15, 0) }

    around { |example| travel_to(Time.utc(2026, 10, 19, 15, 0)) { example.run } }

    def card(owner: ana, value_cents: 300_000)
      pipeline, stage = sale
      account.crm_cards.create!(pipeline: pipeline, stage: stage, owner: owner, title: 'Seguro auto', value_cents: value_cents)
    end

    def ganho
      card.tap { |venda| Crm::Cards::Closer.new(card: venda, actor: ana, result: 'won').perform }
    end

    # Uma hora depois do fechamento.
    def arquivar(venda)
      travel 1.hour
      Crm::Cards::Archiver.new(card: venda, actor: ana).perform
      venda.reload
    end

    def credito
      Crm::Numeros::Credito.new(account: account, user: ana, range: month.range).perform
    end

    it 'guarda o desfecho e mantém a data do fechamento' do
      venda = arquivar(ganho)

      expect(venda).to be_archived
      expect(venda.closed_at).to eq(fechado_em)
      expect(venda.desfecho_arquivado).to eq('won')
      expect(account.crm_cards.com_desfecho(:won)).to contain_exactly(venda)
    end

    it 'continua contando a venda no crédito do mês, nas Metas e no relatório' do
      venda = arquivar(ganho)

      expect(credito).to include(vendas: 1, valores: { 'BRL' => 300_000 }, ganhos: [venda.id])
      vendido = Crm::Metas::Vendido.new(account: account, range: month.range).por_pessoa
      expect(vendido).to eq([sale.first.id, ana.id, 'BRL'] => 300_000)

      resumo = Crm::Reports::Summary.new(account: account, params: { pipeline_id: sale.first.id }).perform
      expect(resumo).to include(won_count: 1, won_value_by_currency: [{ currency: 'BRL', value_cents: 300_000 }])
    end

    it 'card aberto arquivado não vira venda nem ganha data' do
      venda = arquivar(card)

      expect(venda.closed_at).to be_nil
      expect(venda.desfecho_arquivado).to be_nil
      expect(credito).to include(vendas: 0)
    end

    it 'reabrir o arquivado devolve o ganho com a data de antes, sem fechamento novo' do
      venda = arquivar(ganho)

      Crm::Cards::Closer.new(card: venda, actor: ana, result: 'reopen').perform
      venda.reload

      expect(venda).to be_won
      expect(venda.closed_at).to eq(fechado_em)
      expect(venda.metadata).not_to have_key(Crm::Card::DESFECHO_ARQUIVADO)
      expect(venda.activities.where(event_type: 'won').count).to eq(1)
      expect(venda.activities.order(:id).last.payload).to include('desfecho_restaurado' => 'won')
      expect(credito).to include(vendas: 1)
    end

    it 'pedir Ganho no arquivado que era ganho também mantém a data' do
      venda = arquivar(ganho)

      Crm::Cards::Closer.new(card: venda, actor: ana, result: 'won').perform

      expect(venda.reload.closed_at).to eq(fechado_em)
      expect(venda.activities.where(event_type: 'won').count).to eq(1)
    end

    it 'pedir Perdido no arquivado que era ganho é um fechamento novo' do
      venda = arquivar(ganho)

      Crm::Cards::Closer.new(card: venda, actor: ana, result: 'lost').perform

      expect(venda.reload).to be_lost
      expect(venda.closed_at).to eq(Time.current)
      expect(credito).to include(vendas: 0)
    end

    it 'a chave do desfecho só muda junto com o status: editar o metadata não cria venda' do
      venda = arquivar(card)

      venda.update!(metadata: venda.metadata.merge(Crm::Card::DESFECHO_ARQUIVADO => 'won'))
      expect(venda.reload.metadata).not_to have_key(Crm::Card::DESFECHO_ARQUIVADO)

      perdida = card
      Crm::Cards::Closer.new(card: perdida, actor: ana, result: 'lost').perform
      arquivar(perdida).update!(metadata: { Crm::Card::DESFECHO_ARQUIVADO => 'won' })
      expect(perdida.reload.desfecho_arquivado).to eq('lost')
    end

    it 'mudar de funil leva o desfecho como leva o status do card fechado' do
      suporte = account.crm_pipelines.create!(name: 'Suporte', created_by: ana, status: :active, counts_as_sale: false)
      aberto = account.crm_pipeline_stages.create!(pipeline: suporte, name: 'Aberto', position: 0)
      venda = arquivar(ganho)

      venda.update!(pipeline: suporte, stage: aberto)
      expect(venda.reload).to have_attributes(desfecho_arquivado: 'resolved', closed_at: fechado_em)

      venda.update!(pipeline: sale.first, stage: sale.last)
      expect(venda.reload).to have_attributes(desfecho_arquivado: nil, closed_at: nil)
    end
  end
end

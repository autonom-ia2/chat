require 'rails_helper'

# #3097 — o resumo de compras de cada pessoa (Relacionamentos::Compra), o grupo de compra e quando "entrou no grupo"
# dispara a automação. A regra do grupo é a da tela (gruposDeCompra.js); aqui, os casos que separam um grupo do outro.
RSpec.describe Relacionamentos::Compras::Recalcular do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let(:agora) { Time.zone.parse('2026-11-21 12:00:00') }
  let(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:gatilho) { described_class::GATILHO }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  before { travel_to(agora) }

  # Um card ganho há `dias` dias, com o valor em reais (ou na moeda).
  def compra(pessoa, dias:, reais: 100, moeda: 'BRL', status: :won)
    card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: pessoa, title: 'Pedido',
                                     value_cents: reais * 100, currency: moeda, status: status)
    card.tap { |ganho| ganho.update!(closed_at: agora - dias.days) }
  end

  def recalcular(disparar: :venda, contact_ids: nil)
    described_class.new(account, contact_ids: contact_ids, disparar: disparar).call
  end

  def linha(pessoa) = Relacionamentos::Compra.find_by(contact_id: pessoa.id)

  describe 'o resumo' do
    it 'soma os cards ganhos por moeda, com as datas da primeira e da última compra' do
      compra(ana, dias: 40, reais: 300)
      compra(ana, dias: 10, reais: 200)
      compra(ana, dias: 5, reais: 50, moeda: 'USD')

      recalcular

      expect(linha(ana)).to have_attributes(quantas: 3, primeira_em: agora - 40.days, ultima_em: agora - 5.days,
                                            total_brl_cents: 50_000)
      expect(linha(ana).por_moeda).to eq([{ 'moeda' => 'BRL', 'total_cents' => 50_000, 'quantas' => 2 },
                                          { 'moeda' => 'USD', 'total_cents' => 5_000, 'quantas' => 1 }])
    end

    it 'conta o arquivado depois de ganho e deixa de fora aberto, perdido e o arquivado sem desfecho' do
      compra(ana, dias: 10).update!(status: :archived)
      compra(ana, dias: 3, status: :open)
      compra(ana, dias: 3, status: :lost)
      account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: ana, title: 'Parado', status: :archived)

      recalcular

      expect(linha(ana).quantas).to eq(1)
    end

    it 'apaga a linha de quem deixou de ter compra' do
      ganho = compra(ana, dias: 10)
      recalcular
      ganho.update!(status: :open)

      recalcular

      expect(linha(ana)).to be_nil
    end

    it 'não mistura contas' do
      compra(ana, dias: 10)
      outra = create(:account)

      described_class.new(outra, disparar: :tempo).call

      expect(Relacionamentos::Compra.where(account_id: outra.id)).to be_empty
    end
  end

  describe 'o grupo' do
    def grupo_de(*dias_das_compras)
      pessoa = create(:contact, account: account)
      dias_das_compras.each { |dias| compra(pessoa, dias: dias) }
      recalcular(contact_ids: [pessoa.id])
      linha(pessoa).grupo
    end

    it 'separa os grupos pelas faixas do padrão' do
      expect(grupo_de(5)).to eq('compra_novos')
      expect(grupo_de(40, 20)).to eq('compra_fieis')
      expect(grupo_de(40, 30, 20, 10)).to eq('compra_campeoes')
      expect(grupo_de(100)).to eq('compra_em_risco')
      expect(grupo_de(200)).to eq('compra_perdidos')
    end

    # Costume de 10 dias: passou da hora depois de 15 (1,5 vez), antes de chegar a "sem comprar" (90).
    it 'põe em "passou da hora de voltar" quem tem costume e se atrasou, antes de "sem comprar"' do
      expect(grupo_de(26, 16)).to eq('compra_passou_da_hora')
      expect(grupo_de(24, 14)).to eq('compra_fieis')
    end

    it 'segue as faixas que a conta ajustou' do
      account.update!(settings: { 'grupos_de_compra' => { 'campeao_compras' => 2, 'campeao_dias' => 30, 'em_risco_dias' => 60,
                                                          'perdido_dias' => 120 } })

      expect(grupo_de(20, 10)).to eq('compra_campeoes')
      expect(grupo_de(70)).to eq('compra_em_risco')
    end
  end

  describe 'o gatilho "entrou no grupo de compra"' do
    before { allow(Autonomia::Automacao::Escuta).to receive(:comecar) }

    def com_automacao_ligada
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).and_call_original
      ligadas = instance_double(ActiveRecord::Relation, exists?: true)
      allow(Autonomia::Automacao::Escuta).to receive(:automacoes_do_gatilho).with(account.id, gatilho).and_return(ligadas)
    end

    it 'na venda, dispara para quem entra num grupo, inclusive a primeira compra' do
      com_automacao_ligada
      compra(ana, dias: 0)

      recalcular(disparar: :venda, contact_ids: [ana.id])

      expect(Autonomia::Automacao::Escuta).to have_received(:comecar)
        .with(ana, gatilho, evento: "#{gatilho}:#{ana.id}:compra_novos:#{agora.utc.iso8601(6)}",
                            dados: { 'grupo_de_compra' => 'compra_novos' })
    end

    it 'com o tempo, dispara só para quem já estava e mudou de grupo' do
      com_automacao_ligada
      compra(ana, dias: 80)
      recalcular(disparar: false)
      bruno = create(:contact, account: account)
      compra(bruno, dias: 100)
      travel_to(agora + 15.days)

      recalcular(disparar: :tempo)

      expect(linha(ana).grupo).to eq('compra_em_risco')
      expect(Autonomia::Automacao::Escuta).to have_received(:comecar).once
      expect(Autonomia::Automacao::Escuta).to have_received(:comecar)
        .with(ana, gatilho, hash_including(dados: { 'grupo_de_compra' => 'compra_em_risco' }))
    end

    it 'não dispara quando nada mudou, nem no ajuste das faixas' do
      com_automacao_ligada
      compra(ana, dias: 40)
      recalcular(disparar: false)

      recalcular(disparar: :tempo)
      account.update!(settings: { 'grupos_de_compra' => { 'em_risco_dias' => 30, 'campeao_dias' => 10, 'perdido_dias' => 90 } })
      recalcular(disparar: false)

      expect(linha(ana).grupo).to eq('compra_em_risco')
      expect(Autonomia::Automacao::Escuta).not_to have_received(:comecar)
    end

    it 'na venda, não dispara para quem ganha a linha por uma compra antiga' do
      com_automacao_ligada
      compra(ana, dias: 300)

      recalcular(disparar: :venda, contact_ids: [ana.id])

      expect(linha(ana).grupo).to eq('compra_perdidos')
      expect(Autonomia::Automacao::Escuta).not_to have_received(:comecar)
    end

    it 'sem automação ligada com o gatilho, nem lê os contatos' do
      compra(ana, dias: 0)

      recalcular(disparar: :venda, contact_ids: [ana.id])

      expect(Autonomia::Automacao::Escuta).not_to have_received(:comecar)
    end
  end

  describe 'o job' do
    it 'regrupa a conta sem disparar no ajuste das faixas' do
      allow(Autonomia::Automacao::Escuta).to receive(:comecar)
      compra(ana, dias: 40)

      Relacionamentos::Compras::RecalcularJob.perform_now(account.id, nil, false)

      expect(linha(ana).grupo).to eq('compra_novos')
      expect(Autonomia::Automacao::Escuta).not_to have_received(:comecar)
    end
  end

  describe 'o card ganho' do
    it 'enfileira o refazer das compras da pessoa no ganho, depois do commit' do
      card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: ana, title: 'Pedido')

      expect { card.update!(status: :won) }
        .to have_enqueued_job(Relacionamentos::Compras::RecalcularJob).with(account.id, [ana.id], 'venda')
    end

    it 'leva as duas pessoas quando o card ganho muda de pessoa' do
      card = compra(ana, dias: 3)
      bruno = create(:contact, account: account)

      expect { card.update!(contact: bruno) }
        .to have_enqueued_job(Relacionamentos::Compras::RecalcularJob).with(account.id, contain_exactly(ana.id, bruno.id), 'venda')
    end

    it 'o savepoint desfeito não leva o refazer da transação de fora' do
      card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: ana, title: 'Pedido')

      expect do
        Crm::Card.transaction do
          card.update!(status: :won)
          Crm::Card.transaction(requires_new: true) do
            card.update!(value_cents: 500)
            raise ActiveRecord::Rollback
          end
        end
      end.to have_enqueued_job(Relacionamentos::Compras::RecalcularJob).with(account.id, [ana.id], 'venda')
    end

    it 'não enfileira nada no card aberto que muda de título' do
      card = account.crm_cards.create!(pipeline: vendas.first, stage: vendas.last, contact: ana, title: 'Pedido')

      expect { card.update!(title: 'Outro') }.not_to have_enqueued_job(Relacionamentos::Compras::RecalcularJob)
    end
  end
end

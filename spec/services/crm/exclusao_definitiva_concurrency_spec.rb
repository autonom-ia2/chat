require 'rails_helper'
require 'timeout'

# Excluir de vez ao mesmo tempo que outro pedido restaura ou exclui o mesmo item, com duas conexões reais (revisão do
# #2098): o status é relido sob a trava, e o que voltou ao quadro não é apagado.
RSpec.describe Crm::ExclusaoDefinitiva, :crm_travas, :relationships_committed_fixtures do
  self.use_transactional_tests = false

  let!(:account) { create(:account) }
  let!(:admin) { create(:user, account: account, role: :administrator) }
  let!(:funil) { create_crm_pipeline(account: account, user: admin) }
  let!(:card) { account.crm_cards.create!(pipeline: funil.first, stage: funil.last, title: 'Pedido', status: :archived) }
  let(:pronto) { Queue.new }
  let(:soltar) { Queue.new }
  let(:resultados) { Queue.new }

  after do
    soltar << true
    crm_travas_threads.each { |thread| thread.join(1) || thread.kill.join }
  ensure
    apagar_conta_gravada(account, admin)
  end

  # Outra conexão faz `antes` numa transação, avisa e segura as travas até `soltar`.
  def outro_processo(antes)
    aviso = pronto
    espera = soltar
    em_outra_conexao(resultados) do
      ActiveRecord::Base.transaction do
        antes.call
        aviso << true
        espera.pop
      end
      true
    end
    pronto.pop
  end

  def esperar_e_soltar(&)
    esperar_na_trava(em_outra_conexao(resultados, &))
    soltar << true
    crm_travas_threads.each(&:join)
  end

  def auditorias(acao)
    Audited.audit_class.where(auditable: account, action: acao)
  end

  it 'card restaurado enquanto o excluir esperava a trava: nada é apagado' do
    outro_processo(-> { Crm::Card.find(card.id).lock!.update!(status: :open) })

    esperar_e_soltar { Crm::Cards::Excluidor.new(account: account, card_ids: [card.id]).perform && true }

    expect(resultados_de(resultados, 2)).to contain_exactly(true, 'Crm::ExclusaoDefinitiva::Mudou')
    expect(card.reload).to be_open
  end

  it 'funil restaurado enquanto o job esperava a trava: nada é apagado e o motivo fica registrado' do
    funil.first.archived!
    outro_processo(-> { Crm::Pipeline.find(funil.first.id).lock!.update!(status: :active) })

    esperar_e_soltar { Crm::Pipelines::ExcluirDeVezJob.perform_now(funil.first.id, admin.id, 'delete') && true }

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect([funil.first.reload.status, Crm::Card.exists?(card.id)]).to eq(['active', true])
    expect(auditorias(described_class::FALHOU).sole.audited_changes).to include('motivo' => 'not_archived')
    expect(auditorias(described_class::ACAO)).to be_empty
  end

  it 'dois jobs do mesmo pedido ao mesmo tempo: o segundo espera, encontra o funil apagado e sai sem registrar' do
    funil.first.archived!
    primeiro = Crm::Pipelines::Excluidor.new(pipeline: Crm::Pipeline.find(funil.first.id), actor: admin, modo: 'delete')
    aviso = pronto
    espera = soltar
    allow(primeiro).to receive(:apagar_funil!).and_wrap_original do |original, **args|
      original.call(**args).tap do
        aviso << true
        espera.pop
      end
    end
    em_outra_conexao(resultados) { primeiro.perform && true }
    pronto.pop

    esperar_e_soltar { Crm::Pipelines::ExcluirDeVezJob.perform_now(funil.first.id, admin.id, 'delete').nil? }

    expect(resultados_de(resultados, 2)).to eq([true, true])
    expect([Crm::Pipeline.exists?(funil.first.id), Crm::Card.exists?(card.id)]).to eq([false, false])
    expect(auditorias(described_class::ACAO).sole.audited_changes).to include('card_ids' => [card.id])
    expect(auditorias(described_class::FALHOU)).to be_empty
  end
end

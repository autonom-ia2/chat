require 'rails_helper'

# A varredura de minuto em minuto (#2414 F3, ADR-001 2.4 passo 4).
RSpec.describe Autonomia::Automacao::VarreduraJob, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account) }
  let(:definicao) { automacao_ligada(account, admin, [esperar_passo('p1')]) }

  def execucao(**atributos)
    create(:autonomia_automacao_execucao, versao: definicao.versao_ativa, alvo: conversa, **atributos)
  end

  def motivo(execucao) = Autonomia::Automacao::Registro.find_by(execucao: execucao)&.motivo

  it 'fecha como interrompida a que começou e anda há mais de 15 minutos, sem repetir', :aggregate_failures do
    travada = execucao(estado: 'andando', travada_em: 16.minutes.ago)
    andando = execucao(estado: 'andando', travada_em: 1.minute.ago, chave_gatilho: 'outra')

    described_class.perform_now

    expect([travada.reload.estado, motivo(travada), andando.reload.estado]).to eq(%w[interrompida travada andando])
    expect(Autonomia::Automacao::AvancarJob).not_to have_been_enqueued
  end

  it 'a interrompida perde o texto da IA (#2679)' do
    travada = execucao(estado: 'andando', travada_em: 16.minutes.ago, textos: { 'p1' => 'Oi Ana' })

    described_class.perform_now

    expect(travada.reload).to have_attributes(estado: 'interrompida', textos: {})
  end

  it 'reenfileira, com marca nova, a reservada há mais de 15 minutos que nunca começou (fila atrasada)' do
    reservada = execucao(estado: 'andando', travada_em: 16.minutes.ago, due_at: 16.minutes.ago)

    freeze_time do
      described_class.perform_now

      expect([reservada.reload.estado, reservada.travada_em]).to eq(['andando', Time.current])
      expect(Autonomia::Automacao::AvancarJob).to have_been_enqueued.with(reservada.id, Time.current.iso8601(6))
    end
  end

  it 'um erro ao fechar uma não para as outras nem o acordar' do
    vencida = execucao(estado: 'esperando', due_at: 1.minute.ago, chave_gatilho: 'vencida')
    allow(Autonomia::Automacao::Registro).to receive(:create!).and_raise(ActiveRecord::StatementInvalid)
    execucao(estado: 'andando', travada_em: 16.minutes.ago)

    expect { described_class.perform_now }.not_to raise_error
    expect(vencida.reload.estado).to eq('andando')
  end

  it 'fecha como interrompida a aberta vencida cujo alvo foi apagado' do
    orfa = execucao(estado: 'esperando', due_at: 1.minute.ago)
    conversa.delete

    described_class.perform_now

    expect([orfa.reload.estado, motivo(orfa)]).to eq(%w[interrompida alvo_sumiu])
  end

  # #2750, revisão: a busca das órfãs não passa por todas as abertas a cada minuto, só pelas vencidas (índice do due_at).
  it 'a órfã que ainda não venceu fica para quando vencer' do
    orfa = execucao(estado: 'esperando', due_at: 1.day.from_now)
    conversa.delete

    described_class.perform_now
    expect(orfa.reload.estado).to eq('esperando')

    travel(1.day + 1.minute) { described_class.perform_now }
    expect([orfa.reload.estado, motivo(orfa)]).to eq(%w[interrompida alvo_sumiu])
  end

  it 'acorda só quem venceu, com a marca da reserva, uma vez só', :aggregate_failures do
    vencida = execucao(estado: 'esperando', due_at: 1.minute.ago)
    futura = execucao(estado: 'esperando', due_at: 1.minute.from_now, chave_gatilho: 'outra')

    freeze_time do
      described_class.perform_now
      described_class.perform_now

      expect(vencida.reload).to have_attributes(estado: 'andando', travada_em: Time.current)
      expect(futura.reload.estado).to eq('esperando')
      expect(Autonomia::Automacao::AvancarJob).to have_been_enqueued.once.with(vencida.id, Time.current.iso8601(6))
    end
  end

  it 'está agendada a cada minuto' do
    agenda = YAML.load_file(Rails.root.join('config/schedule.yml'))

    expect(agenda['autonomia_automacao_varredura_job']).to include('class' => described_class.name, 'cron' => '* * * * *')
  end
end

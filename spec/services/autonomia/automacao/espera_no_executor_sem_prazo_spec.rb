require 'rails_helper'

# O "esperar até" sem prazo (#2750): a espera só termina pela condição, não tem "se vencer", e nunca fica aberta para
# sempre. O `due_at` dela é a próxima conferência (EsperaNoExecutor::CONFERENCIA): a varredura a acorda, a rodada
# confere o que confere ao retomar e volta a esperar. Fecha com registro e motivo se o alvo for apagado, a automação
# desligada ou quem ligou perder o acesso.
RSpec.describe Autonomia::Automacao::EsperaNoExecutor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:urgente) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' } }
  let(:espera) { { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => 'sem_prazo' } }
  let(:definicao) { automacao_ligada(account, admin, [espera, prioridade_passo('depois', 'low')]) }

  before { ligar_motor(account) }

  after { Current.reset }

  def comecar_e_rodar = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
  def execucao = Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
  def registros = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  describe 'esperando' do
    it 'grava a espera sem prazo: o começo no registro e a próxima conferência no due_at', :aggregate_failures do
      comecar_e_rodar

      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera')
      expect(execucao.due_at).to be_within(1.minute).of(1.day.from_now)
      registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'espera')
      expect(registro.dados).to include('sem_prazo' => true)
      expect(Time.zone.parse(registro.dados['desde'])).to be_within(1.second).of(Time.current)
    end

    it 'a conferência não vence: anos depois, sem a condição, segue esperando, com um registro só', :aggregate_failures do
      comecar_e_rodar

      [1.day + 1.minute, 40.days, 4.years].each { |tempo| travel(tempo) { varrer } }

      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera')
      expect(registros).to eq([['espera', 'ok', nil]])
      expect(conversa.reload.priority).to be_nil
    end

    it 'acorda pela condição e segue', :aggregate_failures do
      comecar_e_rodar
      travel(10.days) do
        conversa.update!(priority: :urgent)
        Autonomia::Automacao::Despertador.acordar(execucao)
        perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob)
      end

      expect(execucao.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
      expect(registros).to eq([['espera', 'ok', nil], ['espera', 'ok', nil], ['depois', 'ok', nil]])
    end

    it 'o aviso que se perdeu é recuperado na conferência: a condição cumprida segue', :aggregate_failures do
      comecar_e_rodar
      conversa.update!(priority: :urgent)

      travel(1.day + 1.minute) { varrer }

      expect(execucao.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'a reserva perdida (o job não chegou) é reenfileirada pela varredura, não fechada como travada', :aggregate_failures do
      comecar_e_rodar
      Autonomia::Automacao::Escuta.reservar(execucao)
      clear_enqueued_jobs

      travel(16.minutes) { varrer }

      expect(execucao).to have_attributes(estado: 'esperando', cursor: 'espera')
      expect(registros).to eq([['espera', 'ok', nil]])
    end

    it 'a limpeza dos 30 dias não leva o registro (o começo) enquanto ela espera; depois de fechada, leva', :aggregate_failures do
      comecar_e_rodar

      travel(40.days) { Autonomia::Automacao::LimparRegistrosJob.perform_now }
      expect(registros).to eq([['espera', 'ok', nil]])

      definicao.desligar!
      travel(40.days) { Autonomia::Automacao::LimparRegistrosJob.perform_now }
      expect(registros).to be_empty
    end
  end

  describe 'nunca fica aberta para sempre' do
    before { comecar_e_rodar }

    it 'a conversa apagada: a varredura fecha com o motivo', :aggregate_failures do
      conversa.destroy!

      varrer

      expect(execucao.estado).to eq('interrompida')
      expect(registros.last).to eq(%w[espera falhou alvo_sumiu])
    end

    it 'a automação desligada: fecha na hora, com o motivo no histórico', :aggregate_failures do
      definicao.desligar!

      expect(execucao.estado).to eq('parada')
      expect(registros.last).to eq(%w[espera pulado desligada])
    end

    it 'a automação pausada por fora (sem passar pelo desligar): a conferência fecha com o motivo', :aggregate_failures do
      definicao.update!(ativa: false)

      travel(1.day + 1.minute) { varrer }

      expect(execucao.estado).to eq('parada')
      expect(registros.last).to eq(%w[espera pulado desligada])
    end

    it 'quem ligou perde o acesso: a conferência fecha com o motivo e pausa a automação', :aggregate_failures do
      AccountUser.find_by!(account: account, user: admin).destroy!

      travel(1.day + 1.minute) { varrer }

      expect(execucao.estado).to eq('parada')
      expect(registros.last).to eq(%w[espera pulado quem_ligou_saiu_da_conta])
      expect(definicao.reload.ativa).to be(false)
    end
  end

  describe 'sem caminho "se vencer"' do
    let(:receita) do
      { 'gatilho' => { 'tipo' => 'conversa.resolvida' },
        'passos' => [espera.merge('se_vencer' => [prioridade_passo('nunca', 'high')])] }
    end

    it 'salvar sem prazo com passos em "se vencer" é recusado, com a frase do passo', :aggregate_failures do
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita)).to be(true)
      problemas = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: nil).problemas

      expect(problemas).to include(I18n.t('autonomia.automacao.receita.sem_prazo_com_se_vencer', passo: 'espera'))
    end

    it 'sem prazo e "se vencer" vazio pode salvar' do
      vazio = receita.deep_merge('passos' => [espera.merge('se_vencer' => [])])

      expect(Autonomia::Automacao::Receita.new(vazio, conta: account, account_user: nil).problemas).to be_empty
    end

    it 'o esquema aceita "sem_prazo" e só ele como texto no prazo', :aggregate_failures do
      expect(Autonomia::Automacao::Receita.esquema_valido?('gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [espera])).to be(true)
      outro = espera.merge('prazo' => 'para_sempre')
      expect(Autonomia::Automacao::Receita.esquema_valido?('gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [outro])).to be(false)
    end
  end
end

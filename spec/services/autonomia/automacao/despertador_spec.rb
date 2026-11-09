require 'rails_helper'

# Revisão do #2816 (lote 4, #2682): o gatilho que acontece de novo com a execução aberta só grava a hora e só acorda a
# espera quando a receita lê `gatilho.repetiu` (EsperaDoGatilho), no mesmo padrão do card e da reunião; e a falha ao
# acordar fica no histórico da execução, não só no log.
RSpec.describe Autonomia::Automacao::Despertador, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open, assignee: admin) }

  before { ligar_motor(account) }

  after { Current.reset }

  def condicao(caminho) = { 'campo' => { '$valor' => caminho }, 'op' => 'igual', 'valor' => true }

  def esperar_ate(caminho, prazo = 30)
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => condicao(caminho), 'prazo' => { 'valor' => prazo, 'unidade' => 'dias' } }
  end

  def rodar(definicao) = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

  def execucao_de(definicao) = Autonomia::Automacao::Execucao.find_by!(automacao: definicao)

  # Os UPDATE na tabela das execuções durante o bloco.
  def updates_nas_execucoes(&)
    updates = []
    contar = lambda do |*, dados|
      sql = dados[:sql]
      updates << sql if sql.start_with?('UPDATE') && sql.include?(Autonomia::Automacao::Execucao.table_name)
    end
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record', &)
    updates
  end

  describe 'o gatilho que repete com a execução aberta' do
    it 'sem espera que leia a repetição, N repetições não gravam nem acordam nada', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_ate('conversa.responsavel_respondeu'), prioridade_passo('ok', 'low')])
      rodar(definicao)
      allow(Autonomia::Automacao::Escuta).to receive(:reservar).and_call_original

      updates = updates_nas_execucoes { 5.times { |dia| travel((dia + 1).days) { rodar(definicao) } } }

      expect(updates).to be_empty
      expect(Autonomia::Automacao::Escuta).not_to have_received(:reservar)
      expect(execucao_de(definicao).repetiu_em).to be_nil
      expect(execucao_de(definicao).estado).to eq('esperando')
    end

    it 'a espera pela resposta do cliente não é reservada pela repetição', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_ate('conversa.cliente_respondeu'), prioridade_passo('ok', 'low')])
      rodar(definicao)
      allow(Autonomia::Automacao::Escuta).to receive(:reservar).and_call_original

      travel(2.days) { rodar(definicao) }

      expect(Autonomia::Automacao::Escuta).not_to have_received(:reservar)
      expect(execucao_de(definicao).estado).to eq('esperando')
      expect(conversa.reload.priority).to be_nil
    end

    it 'com a espera da repetição mais adiante, grava a hora e não acorda a espera de tempo de agora', :aggregate_failures do
      passos = [esperar_passo('antes', 1, 'horas'), esperar_ate('gatilho.repetiu'), prioridade_passo('repetiu', 'low')]
      definicao = automacao_ligada(account, admin, passos)
      rodar(definicao)
      allow(Autonomia::Automacao::Escuta).to receive(:reservar).and_call_original

      travel(10.minutes) { rodar(definicao) }

      expect(Autonomia::Automacao::Escuta).not_to have_received(:reservar)
      expect(execucao_de(definicao).repetiu_em).to be_present
      expect(execucao_de(definicao).cursor).to eq('antes')
    end
  end

  describe 'a falha ao acordar' do
    it 'a reserva quebra na repetição: fica no histórico, e a espera segue pelo relógio', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_ate('gatilho.repetiu'), prioridade_passo('repetiu', 'low')])
      rodar(definicao)
      allow(Autonomia::Automacao::Escuta).to receive(:reservar).and_raise(ActiveRecord::StatementInvalid, 'falha')

      travel(2.days) { rodar(definicao) }

      execucao = execucao_de(definicao)
      registro = Autonomia::Automacao::Registro.find_by!(execucao: execucao, motivo: 'nao_acordou')
      expect([registro.passo, registro.resultado, registro.dados]).to eq(['espera', 'falhou', { 'erro' => 'ActiveRecord::StatementInvalid' }])
      expect(execucao.estado).to eq('esperando')
    end

    it 'a reconferência ao gravar a espera quebra: fica no histórico, e a espera segue pelo relógio', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [esperar_ate('gatilho.repetiu'), prioridade_passo('repetiu', 'low')])
      allow(Autonomia::Automacao::Execucao).to receive(:find_by).and_call_original
      esperando = hash_including(estado: 'esperando')
      allow(Autonomia::Automacao::Execucao).to receive(:find_by).with(esperando).and_raise(ActiveRecord::StatementInvalid, 'falha')

      rodar(definicao)

      execucao = execucao_de(definicao)
      expect(Autonomia::Automacao::Registro.where(execucao: execucao, passo: 'espera', resultado: 'falhou', motivo: 'nao_acordou').count).to eq(1)
      expect(execucao.estado).to eq('esperando')
    end

    it 'o histórico diz o motivo em inglês e em português' do
      chave = 'autonomia.automacao.motivos.nao_acordou'

      expect(%i[en pt_BR].map { |idioma| I18n.exists?(chave, idioma) }).to eq([true, true])
    end
  end
end

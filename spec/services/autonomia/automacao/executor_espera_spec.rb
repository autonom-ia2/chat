require 'rails_helper'

# A espera pedida pelo próprio passo (#2414 G21, #2706): o passo pela porta da ação devolve `:esperar` com o `ate`
# enquanto o mundo não fica pronto (a prospecção espera a conferência de WhatsApp). O executor para no passo sem
# registro, a varredura o acorda na hora pedida, o passo roda de novo e, quando termina, o registro é o dele, com o
# motivo dele (o prazo que venceu é `conferencia_no_prazo`, do próprio passo).
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:resultado) { Autonomia::Automacao::PassoDeAcao::Resultado }
  # O passo de teste devolve, a cada rodada, a próxima resposta da fila.
  let(:passo_de_teste) do
    Class.new do
      cattr_accessor :respostas, :rodadas

      def initialize(**); end

      def executar
        self.class.rodadas += 1
        self.class.respostas.shift.call
      end
    end
  end
  let(:esperar) { -> { resultado.new(tipo: :esperar, motivo: nil, dados: { 'ate' => 2.minutes.from_now }) } }
  let(:pronto) { -> { resultado.new(tipo: :ok, motivo: 'conferencia_no_prazo', dados: { 'cards_criados' => 1 }) } }
  let(:definicao) do
    automacao_ligada(account, admin, [{ 'id' => 'p1', 'tipo' => 'prospeccao', 'faz' => 'recusar' }, prioridade_passo('p2')])
  end

  before do
    ligar_motor(account)
    Autonomia::Prospecting::Config.enable_for!(account)
    # A prospecção de verdade dá lugar ao passo de teste: o PassoDeAcao continua escolhendo o passo pelo tipo.
    allow(Autonomia::Automacao::PassoDeProspeccao).to receive(:new) { passo_de_teste.new }
    passo_de_teste.rodadas = 0
    passo_de_teste.respostas = [esperar, esperar, pronto]
  end

  after { Current.reset }

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  it 'para no passo, sem registro, até a hora que o passo pediu', :aggregate_failures do
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload

    expect([execucao.estado, execucao.cursor, execucao.tentativas]).to eq(['esperando', 'p1', 0])
    expect(execucao.due_at).to be_within(5.seconds).of(2.minutes.from_now)
    expect(registros(execucao)).to be_empty

    travel(1.minute) { varrer }
    expect(passo_de_teste.rodadas).to eq(1)
  end

  it 'acorda na hora, roda o passo de novo e, pronto, segue com o registro e o motivo do passo', :aggregate_failures do
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

    travel(3.minutes) { varrer }
    expect([execucao.reload.estado, passo_de_teste.rodadas]).to eq(['esperando', 2])
    expect(registros(execucao)).to be_empty

    travel(6.minutes) { varrer }
    expect(execucao.reload.estado).to eq('concluida')
    expect(passo_de_teste.rodadas).to eq(3)
    expect(registros(execucao)).to eq([%w[p1 ok conferencia_no_prazo], ['p2', 'ok', nil]])
    expect(conversa.reload.priority).to eq('urgent')
  end

  it 'a espera não gasta as tentativas do erro passageiro' do
    passo_de_teste.respostas = [esperar, -> { resultado.new(tipo: :passageiro, motivo: 'busca_sem_resposta', dados: {}) }]
    execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }

    travel(3.minutes) { varrer }

    expect(execucao.reload.tentativas).to eq(1)
    expect(registros(execucao)).to eq([%w[p1 falhou busca_sem_resposta]])
  end
end

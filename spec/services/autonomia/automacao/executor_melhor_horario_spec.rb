require 'rails_helper'

# #3101: o passo "Mandar mensagem" com `quando: melhor_horario` espera a hora em que o cliente costuma escrever (no
# máximo 24 h) e o histórico diz por quê; quem não tem hora recebe na hora, e a resposta a quem acabou de escrever não
# espera.
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Bruno') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:oi) { mensagem_passo('p1', 'Oi, tudo bem?').merge('quando' => 'melhor_horario') }
  # Quinta-feira, 19/11/2026, 10h em São Paulo (13h UTC); a hora do Bruno é 14h.
  let(:agora) { Time.utc(2026, 11, 19, 13, 0, 0) }
  let(:hora_dele) { Time.utc(2026, 11, 19, 17, contato.id % 60, 0) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.update_columns(settings: account.settings.to_h.merge('reporting_timezone' => 'America/Sao_Paulo')) # rubocop:disable Rails/SkipsModelValidations
  end

  after { Current.reset }

  def aprendido(hora)
    Autonomia::HorarioDeResposta.create!(account: account, contact: contato, por_hora: Array.new(24, 0), respostas: 5, hora: hora,
                                         calculado_em: agora)
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def publicas = conversa.messages.outgoing.where(private: false)

  def rodar(definicao, **partida)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida', **partida).call
    end
  end

  it 'espera a hora do cliente, diz no histórico e manda nela sem esperar de novo', :aggregate_failures do
    aprendido(14)
    execucao = travel_to(agora) { rodar(automacao_ligada(account, admin, [oi])) }

    expect(publicas.count).to eq(0)
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando p1])
    expect(execucao.due_at).to be_within(1.second).of(hora_dele)
    expect(registros(execucao)).to eq([%w[p1 ok adiado_pelo_melhor_horario]])

    travel_to(hora_dele + 1.minute) { varrer }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao)).to eq([%w[p1 ok adiado_pelo_melhor_horario], ['p1', 'ok', nil]])
  end

  it 'manda na hora a quem ainda não tem hora aprendida' do
    execucao = travel_to(agora) { rodar(automacao_ligada(account, admin, [oi])) }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'sem o "quando", manda na hora mesmo com a hora aprendida' do
    aprendido(14)
    execucao = travel_to(agora) { rodar(automacao_ligada(account, admin, [mensagem_passo('p1', 'Oi')])) }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'responde na hora a quem acabou de escrever' do
    aprendido(14)
    entrou = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'quero cotar')
    definicao = automacao_ligada(account, admin, [oi], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = travel_to(agora) { rodar(definicao, chave_gatilho: 'mensagem.criada', mensagem: entrou) }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
  end
end

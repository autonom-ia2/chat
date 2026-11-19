require 'rails_helper'

# #3063, item 2: o limite de mensagens por cliente da conta vale para a mensagem que a automação manda por iniciativa da
# empresa. Fora dele, a execução espera a vaga (sem descartar nem contar tentativa). Resposta a quem está esperando (a
# última mensagem pública da conversa é do cliente) não espera nem conta (combinado com a Automação Ultra, 19/11).
RSpec.describe Autonomia::Automacao::Executor, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Bruno') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:ja_enviada) { 2.days.ago }
  let(:oi) { mensagem_passo('p1', 'Oi, tudo bem?') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.update_columns(settings: account.settings.to_h.merge('ritmo_de_envio' => { 'limite' => { 'mensagens' => 1, 'dias' => 7 } })) # rubocop:disable Rails/SkipsModelValidations
  end

  after { Current.reset }

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def publicas = conversa.messages.outgoing.where(private: false)
  def contados = Autonomia::EnvioAoCliente.where(contact: contato)
  def chegou_ao_limite = Autonomia::EnvioAoCliente.create!(account: account, contact: contato, origem: 'campanha_email', enviado_em: ja_enviada)

  def rodar(definicao, **partida)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: conversa, chave_gatilho: 'conversa.resolvida', **partida).call
    end
  end

  it 'manda e conta quando o cliente ainda tem vaga', :aggregate_failures do
    execucao = rodar(automacao_ligada(account, admin, [oi]))

    expect(publicas.count).to eq(1)
    expect(contados.pluck(:origem)).to eq(['automacao_mensagem'])
    expect(execucao.reload.estado).to eq('concluida')
  end

  it 'no limite, espera a vaga sem mandar e manda quando ela abre', :aggregate_failures do
    chegou_ao_limite
    execucao = rodar(automacao_ligada(account, admin, [oi]))

    vaga = ja_enviada + 7.days + Autonomia::RitmoDeEnvio::Porteiro::FOLGA
    expect(publicas.count).to eq(0)
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando p1])
    expect(execucao.due_at).to be_within(1.second).of(vaga)
    expect(registros(execucao)).to eq([%w[p1 ok adiado_pelo_ritmo]])

    travel_to(vaga + 1.minute) { varrer }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao)).to eq([%w[p1 ok adiado_pelo_ritmo], ['p1', 'ok', nil]])
    expect(contados.count).to eq(2)
  end

  it 'responde na hora a quem acabou de escrever, sem contar', :aggregate_failures do
    chegou_ao_limite
    entrou = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'quero cotar')
    definicao = automacao_ligada(account, admin, [oi], gatilho: { 'tipo' => 'mensagem.criada' })

    execucao = rodar(definicao, chave_gatilho: 'mensagem.criada', mensagem: entrou)

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
    expect(contados.count).to eq(1)
  end

  it 'depois de uma espera em que ninguém respondeu, a resposta atrasada sai e não conta', :aggregate_failures do
    chegou_ao_limite
    entrou = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'quero cotar')
    definicao = automacao_ligada(account, admin, [esperar_passo('e1', 1, 'horas'), oi], gatilho: { 'tipo' => 'mensagem.criada' })
    execucao = rodar(definicao, chave_gatilho: 'mensagem.criada', mensagem: entrou)

    travel_to(2.hours.from_now) { varrer }

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
    expect(contados.count).to eq(1)
  end

  it 'se a equipe respondeu durante a espera, a mensagem seguinte é iniciativa da empresa: passa pelo limite', :aggregate_failures do
    chegou_ao_limite
    entrou = create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'quero cotar')
    definicao = automacao_ligada(account, admin, [esperar_passo('e1', 1, 'horas'), oi], gatilho: { 'tipo' => 'mensagem.criada' })
    execucao = rodar(definicao, chave_gatilho: 'mensagem.criada', mensagem: entrou)
    create(:message, conversation: conversa, account: account, message_type: :outgoing, sender: admin, content: 'Já te mando')

    travel_to(2.hours.from_now) { varrer }

    expect(publicas.count).to eq(1)
    expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando p1])
  end

  it 'nota interna da equipe não conta como resposta: o cliente segue esperando', :aggregate_failures do
    chegou_ao_limite
    create(:message, conversation: conversa, account: account, message_type: :incoming, content: 'quero cotar')
    create(:message, conversation: conversa, account: account, message_type: :outgoing, private: true, sender: admin, content: 'vejo já')

    execucao = rodar(automacao_ligada(account, admin, [oi]))

    expect(publicas.count).to eq(1)
    expect(execucao.reload.estado).to eq('concluida')
  end

  describe 'o galho "a cada mensagem" do "esperar até" (G63)' do
    let(:listener) { Autonomia::AutomacaoListener.instance }
    let(:urgente) { { 'campo' => { '$valor' => 'conversa.prioridade' }, 'op' => 'igual', 'valor' => 'urgent' } }
    let(:espera) do
      { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => urgente, 'prazo' => 'sem_prazo',
        'a_cada_mensagem' => [mensagem_passo('resp', 'Recebi, já vejo para você.')] }
    end

    def cliente_escreve
      mensagem = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming,
                                  sender: contato, content: 'e aí?')
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
        listener.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem))
      end
    end

    it 'no limite, responde na hora a cada mensagem do cliente, sem contar', :aggregate_failures do
      chegou_ao_limite
      execucao = rodar(automacao_ligada(account, admin, [espera]))

      cliente_escreve

      expect(publicas.pluck(:content)).to eq(['Recebi, já vejo para você.'])
      expect(contados.count).to eq(1)
      expect([execucao.reload.estado, execucao.cursor]).to eq(%w[esperando espera])
    end
  end
end

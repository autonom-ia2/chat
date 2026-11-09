require 'rails_helper'

# G8 (#2637): o gatilho "mensagem que falhou". A mensagem que sai para o cliente e o canal recusa (o status passa a
# `failed`, ou ela já nasce assim) começa as automações com o gatilho, na conversa dela. Uma execução por mensagem: a
# marca é a própria mensagem. A falha de uma mensagem que uma automação mandou segue a cadeia de quem mandou: a mesma
# automação não se redispara, e duas que mandam uma para a outra param na profundidade da cadeia.
RSpec.describe Autonomia::Automacao::MensagemQueFalhou, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:execucoes) { Autonomia::Automacao::Execucao }
  let(:falhou) { { 'tipo' => 'mensagem.falhou' } }

  before { ligar_motor(account) }

  after { Current.reset }

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  def enviada(alvo = conversa, **atributos)
    create(:message, conversation: alvo, account: account, inbox: alvo.inbox, message_type: :outgoing, **atributos)
  end

  # O canal recusou: o status muda e o evento leva o antes e o depois, como o `send_update_event` da mensagem.
  def recusar(mensagem)
    mensagem.update!(status: :failed, external_error: '131026: Message undeliverable')
    listener.message_updated(evento('message.updated', message: mensagem, previous_changes: mensagem.previous_changes))
  end

  def falhou_ligada(passos = [esperar_passo('p1')]) = automacao_ligada(account, admin, passos, gatilho: falhou)

  def concluir_tudo
    execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  it 'a mensagem enviada que o canal recusa começa a automação na conversa, marcada pela mensagem', :aggregate_failures do
    definicao = falhou_ligada
    mensagem = enviada

    recusar(mensagem)

    execucao = execucoes.sole
    expect(execucao).to have_attributes(automacao_id: definicao.id, alvo: conversa, chave_gatilho: 'mensagem.falhou',
                                        evento: "mensagem.falhou:#{mensagem.id}")
  end

  it 'o mesmo evento entregue de novo não abre outra execução, nem com a primeira já fechada' do
    falhou_ligada
    mensagem = enviada
    recusar(mensagem)
    concluir_tudo

    listener.message_updated(evento('message.updated', message: mensagem, previous_changes: { 'status' => %w[sent failed] }))

    expect(execucoes.count).to eq(1)
  end

  it 'a mensagem que já nasce recusada começa a automação' do
    falhou_ligada
    mensagem = enviada(status: :failed, external_error: 'janela fechada')

    listener.message_created(evento('message.created', message: mensagem))

    expect(execucoes.sole.evento).to eq("mensagem.falhou:#{mensagem.id}")
  end

  it 'não começa: mensagem entregue, lida, recebida, nota privada ou outra mudança da mensagem já recusada', :aggregate_failures do
    falhou_ligada
    entregue = enviada
    entregue.update!(status: :delivered)
    listener.message_updated(evento('message.updated', message: entregue, previous_changes: entregue.previous_changes))

    recebida = create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: :incoming, status: :failed)
    listener.message_created(evento('message.created', message: recebida))

    nota = enviada(private: true, status: :failed)
    listener.message_created(evento('message.created', message: nota))

    recusada = enviada(status: :failed)
    recusada.update!(content: 'editada')
    listener.message_updated(evento('message.updated', message: recusada, previous_changes: recusada.previous_changes))

    expect(execucoes.count).to eq(0)
  end

  it 'só a automação com o gatilho: a de "mensagem criada" não começa pela falha' do
    falhou_ligada
    criada = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada' })

    recusar(enviada)

    expect(execucoes.where(automacao: criada)).to be_empty
  end

  it 'rajada: 5 mensagens recusadas em 5 conversas abrem 5 execuções, uma por mensagem' do
    definicao = falhou_ligada
    conversas = create_list(:conversation, 5, account: account, status: :open)

    conversas.each { |alvo| recusar(enviada(alvo)) }

    expect(execucoes.where(automacao: definicao).pluck(:alvo_id)).to match_array(conversas.map(&:id))
  end

  it 'conta sem o motor não consulta automação nenhuma' do
    falhou_ligada
    mensagem = enviada
    account.disable_features!('automacao_motor')

    consultas = []
    contar = ->(*, dados) { consultas << dados[:sql] }
    ActiveSupport::Notifications.subscribed(contar, 'sql.active_record') { recusar(mensagem) }

    expect(consultas.select { |sql| sql.include?('autonomia_automacao') }).to be_empty
  end

  describe 'a falha da mensagem que uma automação mandou' do
    # A mensagem que o passo "mensagem" mandou leva a marca da execução (NaConversa#marca).
    def mandada_por(definicao)
      execucao = execucoes.create!(account: account, automacao: definicao, versao: definicao.versao_ativa, alvo: conversa,
                                   chave_gatilho: 'mensagem.falhou', estado: 'concluida', finalizada_em: Time.current,
                                   cadeia: ["automacao:#{definicao.id}"], profundidade: 1, evento: "spec:#{SecureRandom.hex(4)}")
      enviada(content_attributes: { automacao_id: definicao.id, execucao_id: execucao.id, passo: 'p1' })
    end

    it 'não redispara a própria automação: a cadeia de quem mandou barra o auto-disparo', :aggregate_failures do
      definicao = falhou_ligada
      mensagem = mandada_por(definicao)

      recusar(mensagem)

      expect(execucoes.where(automacao: definicao).count).to eq(1)
      expect(execucoes.where(evento: "mensagem.falhou:#{mensagem.id}")).to be_empty
    end

    it 'dispara outra automação, que herda a cadeia de quem mandou', :aggregate_failures do
      quem_mandou = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: { 'tipo' => 'conversa.resolvida' })
      avisa = falhou_ligada
      mensagem = mandada_por(quem_mandou)

      recusar(mensagem)

      execucao = execucoes.find_by!(automacao: avisa)
      expect(execucao.cadeia).to eq(["automacao:#{quem_mandou.id}", "automacao:#{avisa.id}"])
    end

    it 'duas automações que se mandam mensagem que falha param na cadeia, sem laço', :aggregate_failures do
      a = falhou_ligada
      b = falhou_ligada

      recusar(mandada_por(a))
      de_b = execucoes.where(automacao: b).where('evento LIKE ?', 'mensagem.falhou:%').sole
      expect(de_b.cadeia).to eq(["automacao:#{a.id}", "automacao:#{b.id}"])

      # A mensagem que a B mandou falha: a A já está na cadeia (laço) e a B é ela mesma (auto-disparo). Nada começa.
      recusar(enviada(content_attributes: { automacao_id: b.id, execucao_id: de_b.id, passo: 'p1' }))

      expect(execucoes.where('evento LIKE ?', 'mensagem.falhou:%').count).to eq(1)
    end
  end

  it 'pela plataforma: a mudança de status despacha message.updated e a escuta começa a automação' do
    falhou_ligada
    mensagem = enviada
    clear_enqueued_jobs

    perform_enqueued_jobs(only: EventDispatcherJob) { mensagem.update!(status: :failed, external_error: 'recusada') }

    expect(execucoes.sole.evento).to eq("mensagem.falhou:#{mensagem.id}")
  end
end

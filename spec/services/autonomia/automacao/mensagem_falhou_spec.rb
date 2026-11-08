require 'rails_helper'

# G8 (#2637): o gatilho "mensagem.falhou". A mensagem enviada ao cliente que o canal recusa, na hora ou depois (a Meta
# avisa a falha mais tarde), começa a automação na conversa dela, uma vez por mensagem. Ex. 19: o WhatsApp recusa e o
# mesmo texto vai por e-mail (`envio.texto` é o da mensagem que falhou).
RSpec.describe Autonomia::Automacao::MensagemFalhou, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:contato) { create(:contact, account: account, name: 'Bruno', email: 'bruno@exemplo.com.br') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }
  let(:falhou) { { 'tipo' => 'mensagem.falhou' } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def execucoes(definicao) = Autonomia::Automacao::Execucao.where(automacao: definicao)

  def enviada(conversa_alvo = conversa, **atributos)
    create(:message, account: account, conversation: conversa_alvo, inbox: conversa_alvo.inbox, message_type: :outgoing,
                     content: 'Sua apólice vence em 30 dias.', **atributos)
  end

  def criada(mensagem)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      listener.message_created(Events::Base.new('message.created', Time.zone.now, message: mensagem))
    end
  end

  # O canal avisa a situação nova: a mensagem muda e o evento chega à escuta.
  def canal_avisa(mensagem, status)
    mensagem.update!(status: status)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: mensagem, previous_changes: mensagem.previous_changes))
    end
  end

  it 'a recusa depois do envio começa a automação na conversa, com a marca da mensagem', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)
    mensagem = enviada

    canal_avisa(mensagem, :failed)

    execucao = execucoes(definicao).sole
    expect(execucao).to have_attributes(alvo: conversa, chave_gatilho: 'mensagem.falhou', evento: "mensagem.falhou:#{mensagem.id}",
                                        estado: 'concluida')
  end

  it 'a mensagem que já nasce falhada também começa' do
    definicao = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)

    criada(enviada(status: :failed))

    expect(execucoes(definicao).count).to eq(1)
  end

  it 'o aviso repetido do canal não abre outra execução' do
    definicao = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)
    mensagem = enviada

    canal_avisa(mensagem, :failed)
    listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: mensagem, previous_changes: { 'status' => %w[sent failed] }))

    expect(execucoes(definicao).count).to eq(1)
  end

  it 'entregue, lida, mensagem recebida ou nota privada não começam', :aggregate_failures do
    definicao = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)

    canal_avisa(enviada, :delivered)
    canal_avisa(enviada, :read)
    criada(create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :incoming, status: :failed))
    criada(enviada(private: true, status: :failed))

    expect(execucoes(definicao)).to be_empty
  end

  it 'a automação que mandou a mensagem não começa de novo por ela; outra começa', :aggregate_failures do
    propria = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)
    outra = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)

    canal_avisa(enviada(content_attributes: { 'automacao_id' => propria.id }), :failed)

    expect(execucoes(propria)).to be_empty
    expect(execucoes(outra).count).to eq(1)
  end

  it 'duas automações "falhou → manda" não giram uma na outra', :aggregate_failures do
    reenvia = [mensagem_passo('de_novo', 'Tentando de novo.')]
    a = automacao_ligada(account, admin, reenvia, gatilho: falhou)
    b = automacao_ligada(account, admin, reenvia, gatilho: falhou)
    canal_avisa(enviada, :failed)
    expect(execucoes(a).count + execucoes(b).count).to eq(2)

    reenvios = conversa.messages.outgoing.select { |item| item.content_attributes.to_h['passo'] == 'de_novo' }
    expect(reenvios.size).to eq(2)
    travel(10.minutes) { reenvios.each { |item| canal_avisa(item, :failed) } }

    expect(execucoes(a).count + execucoes(b).count).to eq(2)
  end

  it 'rajada: N mensagens recusadas em N conversas abrem N execuções, sem laço', :aggregate_failures do
    email = { 'id' => 'email', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Aviso'],
              'texto' => [{ '$valor' => 'envio.texto' }] }
    definicao = automacao_ligada(account, admin, [email], gatilho: falhou)
    conversas = create_list(:conversation, 3, account: account, status: :open)

    conversas.each { |item| canal_avisa(enviada(item), :failed) }

    expect(execucoes(definicao).map(&:alvo)).to match_array(conversas)
    expect(execucoes(definicao).pluck(:estado).uniq).to eq(['concluida'])
  end

  it 'envio.texto e envio.situacao são os da mensagem que falhou, até o primeiro envio da execução', :aggregate_failures do
    email = { 'id' => 'email', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Sua apólice'],
              'texto' => [{ '$valor' => 'envio.texto' }, ' Qual é o seu número novo?'] }
    so_se_falhou = { 'id' => 'se', 'tipo' => 'se', 'entao' => [email], 'senao' => [],
                     'condicao' => { 'campo' => { '$valor' => 'envio.situacao' }, 'op' => 'igual', 'valor' => 'falhou' } }
    definicao = automacao_ligada(account, admin, [so_se_falhou], gatilho: falhou)

    canal_avisa(enviada, :failed)

    expect(execucoes(definicao).sole.estado).to eq('concluida')
    expect(Message.where(inbox: caixa_de_email).sole.content).to eq('Sua apólice vence em 30 dias. Qual é o seu número novo?')
  end

  it 'a mensagem da marca vale só na conversa do alvo' do
    definicao = automacao_ligada(account, admin, [avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Não chegou')], gatilho: falhou)
    canal_avisa(enviada, :failed)
    execucao = execucoes(definicao).sole
    de_outra = enviada(create(:conversation, account: account, status: :open))
    execucao.update!(evento: "mensagem.falhou:#{de_outra.id}")

    expect(Autonomia::Automacao::Contexto.de(conversa, execucao: execucao).ultimo_envio).to be_nil
  end
end

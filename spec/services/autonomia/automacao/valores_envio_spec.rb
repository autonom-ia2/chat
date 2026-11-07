require 'rails_helper'

# #2680: a mensagem que a automação mandou vira valor (`envio.texto`, `envio.situacao`), e a mudança da situação acorda
# o "esperar até". É o ramo "se o WhatsApp recusar, manda por e-mail o mesmo texto" do ex. 1, sem gatilho de falha.
RSpec.describe Autonomia::Automacao::Valores, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator, name: 'Ana Souza') }
  let(:contato) { create(:contact, account: account, name: 'Bruno', email: 'bruno@exemplo.com.br') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:caixa_de_email) { create(:channel_email, account: account).inbox }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def rodar(passos)
    definicao = automacao_ligada(account, admin, passos)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
    Autonomia::Automacao::Execucao.find_by!(automacao: definicao)
  end

  def registros(execucao)
    Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)
  end

  def situacao(valor, operador = 'igual') = { 'campo' => { '$valor' => 'envio.situacao' }, 'op' => operador, 'valor' => valor }

  def ler(execucao, caminho)
    contexto = Autonomia::Automacao::Contexto.de(conversa, execucao: execucao)
    described_class.new(alvo: contexto, quem: admin).ler(caminho)
  end

  # O canal confirma: a mensagem muda de situação e o evento chega à escuta, com as rodadas que ele acorda.
  def canal_confirma(mensagem, status)
    mensagem.update!(status: status)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: mensagem, previous_changes: mensagem.previous_changes))
    end
  end

  def oi = mensagem_passo('oi', 'Oi ', { '$valor' => 'contato.nome' }, ', sua apólice vence em 30 dias.')

  # Espera o canal dizer se chegou; se falhou, o mesmo texto vai por e-mail.
  def passos_do_ramo
    espera = { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => situacao('saiu', 'diferente'),
               'prazo' => { 'valor' => 1, 'unidade' => 'horas' } }
    email = { 'id' => 'email', 'tipo' => 'email', 'caixa_id' => caixa_de_email.id, 'assunto' => ['Sua apólice'],
              'texto' => [{ '$valor' => 'envio.texto' }] }
    [oi, espera, { 'id' => 'se', 'tipo' => 'se', 'condicao' => situacao('falhou'), 'entao' => [email], 'senao' => [] }]
  end

  it 'lê o texto e a situação da última mensagem que a execução mandou', :aggregate_failures do
    execucao = rodar([oi])
    mensagem = conversa.messages.outgoing.last

    expect(ler(execucao, 'envio.texto')).to eq('Oi Bruno, sua apólice vence em 30 dias.')
    expect(ler(execucao, 'envio.situacao')).to eq('saiu')

    mensagem.update!(status: :delivered)
    expect(ler(execucao, 'envio.situacao')).to eq('entregue')
  end

  it 'antes do primeiro envio, e a nota do "avisar", leem vazio' do
    execucao = rodar([avisar_passo('aviso', { 'pessoas' => [admin.id] }, 'Olha esta conversa')])

    expect(ler(execucao, 'envio.texto')).to be_nil
  end

  it 'o WhatsApp recusa: a espera acorda na hora e o mesmo texto sai por e-mail', :aggregate_failures do
    execucao = rodar(passos_do_ramo)
    expect(execucao.reload.estado).to eq('esperando')

    travel(2.minutes) { canal_confirma(conversa.messages.outgoing.last, :failed) }

    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao).map(&:first)).to eq(%w[oi espera espera se email])
    expect(Message.where(inbox: caixa_de_email).last.content).to eq('Oi Bruno, sua apólice vence em 30 dias.')
  end

  it 'entregue: segue sem e-mail', :aggregate_failures do
    execucao = rodar(passos_do_ramo)

    travel(2.minutes) { canal_confirma(conversa.messages.outgoing.last, :delivered) }

    expect(execucao.reload.estado).to eq('concluida')
    expect(registros(execucao).map(&:first)).not_to include('email')
  end

  it 'mudança que não é a situação, ou de mensagem sem a marca da automação, não acorda ninguém', :aggregate_failures do
    execucao = rodar(passos_do_ramo)
    outra = create(:message, account: account, conversation: conversa, inbox: conversa.inbox, message_type: :outgoing)

    travel(2.minutes) do
      canal_confirma(outra, :failed)
      mensagem = conversa.messages.outgoing.where.not(id: outra.id).last
      mensagem.update!(content_attributes: mensagem.content_attributes.merge('editada' => true))
      listener.message_updated(Events::Base.new('message.updated', Time.zone.now, message: mensagem, previous_changes: mensagem.previous_changes))
    end

    expect(execucao.reload.estado).to eq('esperando')
  end
end

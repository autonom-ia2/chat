require 'rails_helper'

# #2729: o filtro "a mensagem tem foto ou PDF" (`mensagem.tem_anexo`) da Automação livre no e-mail. A caixa cria a
# mensagem e grava os anexos na mesma transação (Imap::ImapMailbox#process, MailboxHelper): o `message.created` sai no
# commit, com os anexos já gravados. Pelo despacho real (EventDispatcherJob → Escuta → Partida), o filtro lê "sim" no
# e-mail com foto e "não" no e-mail só de texto.
RSpec.describe Imap::ImapMailbox, :automacao_motor do
  include ActionMailbox::TestHelper
  include ActiveJob::TestHelper

  let(:channel) { create(:channel_email, :imap_email) }
  let(:account) { channel.account }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:com_anexo) { { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => true } }
  let(:sem_anexo) { { 'campo' => { '$valor' => 'mensagem.tem_anexo' }, 'op' => 'igual', 'valor' => false } }

  before { ligar_motor(account) }

  after { Current.reset }

  def ligada(filtro) = automacao_ligada(account, admin, [prioridade_passo('p1')], gatilho: { 'tipo' => 'mensagem.criada', 'filtros' => [filtro] })

  def chega(mail)
    perform_enqueued_jobs(only: [EventDispatcherJob, Autonomia::Automacao::AvancarJob]) { described_class.new.process(mail, channel) }
    Message.where(inbox: channel.inbox).incoming.last
  end

  def execucoes(definicao, mensagem) = Autonomia::Automacao::Execucao.where(automacao: definicao, alvo: mensagem.conversation)

  it 'o e-mail com foto chega à automação com o anexo gravado: o filtro lê "sim"', :aggregate_failures do
    tem = ligada(com_anexo)
    nao_tem = ligada(sem_anexo)

    mensagem = chega(create_inbound_email_from_fixture('attachments_without_text.eml').mail)

    expect(mensagem.attachments.count).to eq(2)
    expect(execucoes(tem, mensagem).count).to eq(1)
    expect(execucoes(nao_tem, mensagem)).to be_empty
  end

  it 'o e-mail só de texto continua lendo "não"', :aggregate_failures do
    tem = ligada(com_anexo)
    nao_tem = ligada(sem_anexo)

    mensagem = chega(create_inbound_email_from_mail(from: 'cliente@exemplo.com', to: 'imap@gmail.com', body: 'Só texto').mail)

    expect(mensagem.attachments).to be_empty
    expect(execucoes(tem, mensagem)).to be_empty
    expect(execucoes(nao_tem, mensagem).count).to eq(1)
  end
end

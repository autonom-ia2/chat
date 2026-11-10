require 'rails_helper'

# G46 (exemplo 14, o laço dos documentos): `conversa.cliente_mandou_documento`, o "esperar até o cliente mandar foto ou
# PDF". Conta só o documento (FotoOuPdf) que chegou durante a espera, na conversa da execução (a mesma que o `le: anexos`
# lê) e só se quem ligou a vê. Texto e áudio ("já mando") acordam a espera, mas não a cumprem.
RSpec.describe Autonomia::Automacao::Resposta, :automacao_motor do
  include ActiveJob::TestHelper

  let(:listener) { Autonomia::AutomacaoListener.instance }
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:atendente) { create(:user, account: account, role: :agent) }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before { ligar_motor(account) }

  after { Current.reset }

  def documento_chegou = { 'campo' => { '$valor' => 'conversa.cliente_mandou_documento' }, 'op' => 'igual', 'valor' => true }

  def esperar_documento
    { 'id' => 'espera', 'tipo' => 'esperar_ate', 'condicao' => documento_chegou, 'prazo' => { 'valor' => 2, 'unidade' => 'dias' },
      'se_vencer' => [prioridade_passo('sem_documento', 'high'), { 'id' => 'fim', 'tipo' => 'parar' }] }
  end

  def evento(nome, **dados) = Events::Base.new(nome, Time.zone.now, dados)

  # A mensagem como o canal grava (o anexo junto) e o evento dela na escuta, com as rodadas que ele acorda.
  def manda(midia = nil, onde: conversa, texto: nil)
    mensagem = onde.messages.new(account: account, inbox: onde.inbox, message_type: :incoming, sender: onde.contact, content: texto)
    anexar(mensagem, midia) if midia
    mensagem.save!
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { listener.message_created(evento('message.created', message: mensagem)) }
    mensagem
  end

  def anexar(mensagem, midia)
    file_type, content_type, arquivo = { foto: [:image, 'image/png', 'sample.png'], pdf: [:file, 'application/pdf', 'sample.pdf'],
                                         audio: [:audio, 'audio/ogg', 'sample.ogg'] }.fetch(midia)
    anexo = mensagem.attachments.new(account_id: account.id, file_type: file_type)
    anexo.file.attach(io: Rails.root.join('spec/assets', arquivo).open, filename: arquivo, content_type: content_type, identify: false)
  end

  def passos(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado)

  describe 'no "esperar até"' do
    let(:definicao) { automacao_ligada(account, admin, [esperar_documento, prioridade_passo('chegou', 'low')]) }
    let!(:execucao) { perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }.reload }

    it 'a foto durante a espera cumpre na hora', :aggregate_failures do
      expect(execucao.estado).to eq('esperando')

      travel(3.hours) { manda(:foto) }

      expect(execucao.reload.estado).to eq('concluida')
      expect(conversa.reload.priority).to eq('low')
    end

    it 'o PDF também cumpre' do
      travel(1.day) { manda(:pdf) }

      expect(execucao.reload.estado).to eq('concluida')
    end

    it '"já mando" em texto e o áudio acordam, mas não cumprem nem recomeçam a conta', :aggregate_failures do
      prazo = execucao.due_at

      travel(1.hour) { manda(texto: 'já mando') }
      travel(2.hours) { manda(:audio) }

      expect([execucao.reload.estado, execucao.due_at]).to eq(['esperando', prazo])
    end

    it 'o documento em outra conversa do contato não conta: só a da execução', :aggregate_failures do
      outra = create(:conversation, account: account, inbox: conversa.inbox, contact: conversa.contact, status: :open)

      travel(1.hour) { manda(:foto, onde: outra) }

      expect(execucao.reload.estado).to eq('esperando')
    end

    it 'o documento de antes da espera não conta, e vencido o prazo sai pelo "se vencer"', :aggregate_failures do
      travel(2.days + 1.minute) { varrer }

      expect(execucao.reload.estado).to eq('concluida')
      expect(passos(execucao)).to eq([%w[espera ok], %w[espera pulado], %w[sem_documento ok], %w[fim ok]])
    end
  end

  describe 'a janela e quem ligou' do
    let(:espera) { 1.hour.ago.. }

    def documento?(quem)
      described_class::VALORES.fetch('conversa.cliente_mandou_documento').call(Autonomia::Automacao::Contexto.de(conversa), espera, quem)
    end

    it 'o documento antes da janela não conta' do
      travel(-2.hours) { manda(:foto) }

      expect(documento?(admin)).to be(false)
    end

    it 'na conversa que quem ligou não vê, não conta; para quem vê, conta', :aggregate_failures do
      manda(:foto)

      expect(documento?(atendente)).to be(false)
      expect(documento?(admin)).to be(true)
      expect(documento?(nil)).to be(false)
    end

    it 'sem conversa (o contato antes da conversa nova), nenhum documento chegou' do
      manda(:foto)
      contexto = Autonomia::Automacao::Contexto.de(conversa.contact)

      expect(described_class::VALORES.fetch('conversa.cliente_mandou_documento').call(contexto, espera, admin)).to be(false)
    end
  end
end

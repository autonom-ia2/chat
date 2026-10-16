require 'rails_helper'

# Registro por envio fora da janela (#1585, tabela própria): o Followup IA chama depois do `:sent` do MessageSender.
RSpec.describe Whatsapp::Templates::EnvioForaDaJanela::Registro do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing) }
  let(:consentimento) do
    WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU, versao_aviso: 'v1',
                                    texto_aviso: 'Aviso.')
  end
  let(:follow_up) do
    Crm::FollowUp.create!(account: account, contact: conversation.contact, conversation: conversation, inbox: inbox,
                          title: 'Andamento', due_at: 1.hour.from_now)
  end
  # O `envio_fora_da_janela` que o `enviar` devolve no metadata, mais o que o Followup acrescenta.
  let(:registro) do
    { 'tipo' => 'andamento', 'caminho' => 'modelo', 'escolha' => 'do_tipo', 'modelo' => 'c2y_andamento_1', 'idioma' => 'pt_BR',
      'categoria' => 'UTILITY', 'origem' => 'sistema', 'consentimento_id' => consentimento.id, 'crm_follow_up_id' => follow_up.id }
  end

  def registrar(dados = registro, mensagem: message)
    Whatsapp::Templates::EnvioForaDaJanela.registrar_envio(message: mensagem, registro: dados)
  end

  it 'grava os campos do registro, com conta e caixa da mensagem' do
    linha = registrar(registro.merge('motivo' => 'pre_voo'))

    expect(linha).to be_persisted
    expect(linha.reload).to have_attributes(
      account_id: account.id, inbox_id: inbox.id, message_id: message.id, crm_follow_up_id: follow_up.id,
      whatsapp_template_consent_id: consentimento.id, tipo: 'andamento', caminho: 'modelo', escolha: 'do_tipo',
      template_name: 'c2y_andamento_1', template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema', motivo: 'pre_voo'
    )
  end

  it 'aceita chaves em símbolo e sem os opcionais' do
    linha = registrar(registro.except('crm_follow_up_id', 'consentimento_id', 'escolha').symbolize_keys)

    expect(linha.reload).to have_attributes(crm_follow_up_id: nil, whatsapp_template_consent_id: nil, escolha: nil, motivo: nil)
  end

  it 'idempotente: a mesma mensagem não grava duas vezes e devolve a linha já gravada' do
    primeira = registrar

    expect { expect(registrar(registro.merge('tipo' => 'retorno'))).to eq(primeira) }.not_to change(WhatsappOutOfWindowSend, :count)
    expect(primeira.reload.tipo).to eq('andamento')
  end

  # A outra gravação vem de outra conexão: aqui ela já está no banco e a busca deste processo ainda não a viu. O
  # `create!` precisa ter sido tentado, senão o spec passaria sem provar o caminho do índice único.
  it 'corrida: outra gravação da mesma mensagem entre a busca e o INSERT esbarra no índice único e vale a que ganhou' do
    vencedora = registrar(registro.merge('tipo' => 'retorno'))
    buscas = 0
    allow(WhatsappOutOfWindowSend).to receive(:find_by).and_wrap_original do |original, *args|
      (buscas += 1) == 1 ? nil : original.call(*args)
    end
    allow(WhatsappOutOfWindowSend).to receive(:create!).and_call_original

    expect(registrar).to eq(vencedora)
    expect(WhatsappOutOfWindowSend).to have_received(:create!).once
    expect(WhatsappOutOfWindowSend.where(message_id: message.id).pluck(:tipo)).to eq(['retorno'])
  end

  describe 'erro não propaga' do
    before { allow(Rails.logger).to receive(:error) }

    it 'registro inválido: devolve nil e loga só a classe e os ids, sem gravar' do
      expect(registrar(registro.except('tipo'))).to be_nil

      expect(WhatsappOutOfWindowSend.count).to eq(0)
      expect(Rails.logger).to have_received(:error)
        .with("#{described_class::LOG} account_id=#{account.id} message_id=#{message.id} ActiveRecord::RecordInvalid")
    end

    it 'autorização ou follow-up inexistente (sem FK, quem confere é o model): devolve nil, sem gravar' do
      expect(registrar(registro.merge('consentimento_id' => 0))).to be_nil
      expect(registrar(registro.merge('crm_follow_up_id' => 0))).to be_nil

      expect(WhatsappOutOfWindowSend.count).to eq(0)
      expect(Rails.logger).to have_received(:error)
        .with("#{described_class::LOG} account_id=#{account.id} message_id=#{message.id} ActiveRecord::RecordInvalid").twice
    end

    it 'manda ao rastreador de erros só os ids e a classe, sem a mensagem do erro original' do
      allow(WhatsappOutOfWindowSend).to receive(:create!).and_raise(ActiveRecord::StatementInvalid, 'DETAIL: texto do cliente')
      rastreador = instance_double(ChatwootExceptionTracker, capture_exception: nil)
      allow(ChatwootExceptionTracker).to receive(:new).and_return(rastreador)

      expect(registrar).to be_nil

      expect(ChatwootExceptionTracker).to have_received(:new) do |erro|
        expect(erro).to be_a(described_class::Falhou)
        expect(erro.message).to eq("#{described_class::LOG} account_id=#{account.id} message_id=#{message.id} ActiveRecord::StatementInvalid")
      end
      expect(rastreador).to have_received(:capture_exception).once
    end

    it 'banco recusa o comando: devolve nil e a transação de quem chama segue válida (savepoint)' do
      allow(WhatsappOutOfWindowSend).to receive(:create!) { WhatsappOutOfWindowSend.connection.execute('SELECT 1/0') }
      resultado = nil
      ActiveRecord::Base.transaction do
        resultado = registrar
        expect(Account.exists?(account.id)).to be(true)
      end

      expect(resultado).to be_nil
      expect(Rails.logger).to have_received(:error).with(a_string_ending_with("message_id=#{message.id} ActiveRecord::StatementInvalid"))
    end

    it 'mensagem ausente, não gravada ou registro que não é hash: devolve nil' do
      expect(registrar(mensagem: nil)).to be_nil
      expect(registrar(mensagem: build(:message, account: account, inbox: inbox, conversation: conversation))).to be_nil
      expect(registrar('andamento')).to be_nil
      expect(WhatsappOutOfWindowSend.count).to eq(0)
    end

    it 'follow-up ou autorização de outra conta: devolve nil, sem gravar' do
      outra = create(:account)
      alheio = WhatsappTemplateConsent.create!(account: outra, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                               versao_aviso: 'v1', texto_aviso: 'Aviso.')

      follow_up_alheio = Crm::FollowUp.create!(account: outra, contact: create(:contact, account: outra), title: 'Retorno',
                                               due_at: 1.hour.from_now)

      expect(registrar(registro.merge('consentimento_id' => alheio.id))).to be_nil
      expect(registrar(registro.merge('crm_follow_up_id' => follow_up_alheio.id))).to be_nil
      expect(WhatsappOutOfWindowSend.count).to eq(0)
    end
  end
end

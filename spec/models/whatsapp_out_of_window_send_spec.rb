require 'rails_helper'

# Registro append-only de cada envio fora da janela (#1585): linha gravada não muda nem sai pelo app.
RSpec.describe WhatsappOutOfWindowSend do
  let(:inbox) { create(:inbox) }

  def gravar
    described_class.create!(account: inbox.account, inbox: inbox, tipo: 'andamento', caminho: 'modelo', escolha: 'do_tipo',
                            template_name: 'c2y_andamento_1', template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema')
  end

  it 'linha gravada não muda: update, update_columns e destroy são recusados' do
    linha = gravar

    expect { linha.update!(tipo: 'retorno') }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { linha.update_columns(tipo: 'retorno') }.to raise_error(ActiveRecord::ReadOnlyRecord) # rubocop:disable Rails/SkipsModelValidations
    expect { linha.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(described_class.find(linha.id)).to have_attributes(tipo: 'andamento')
  end

  it 'exige tipo, caminho, modelo, idioma, categoria e origem' do
    linha = described_class.new(account: inbox.account, inbox: inbox)

    expect(linha).not_to be_valid
    expect(linha.errors.attribute_names).to include(:tipo, :caminho, :template_name, :template_language, :categoria, :origem)
  end

  it 'conta ou caixa apagada leva o registro (on_delete: cascade)' do
    da_caixa = gravar
    Inbox.where(id: inbox.id).delete_all
    expect(described_class.exists?(da_caixa.id)).to be(false)

    outra = create(:inbox)
    da_conta = described_class.create!(account: outra.account, inbox: outra, tipo: 'retorno', caminho: 'modelo', template_name: 'x',
                                       template_language: 'pt_BR', categoria: 'UTILITY', origem: 'conta')
    Account.where(id: outra.account_id).delete_all
    expect(described_class.exists?(da_conta.id)).to be(false)
  end

  it 'mensagem, follow-up e autorização apagados só soltam a referência (on_delete: nullify)' do
    account = inbox.account
    conversation = create(:conversation, account: account, inbox: inbox)
    message = create(:message, account: account, inbox: inbox, conversation: conversation)
    follow_up = Crm::FollowUp.create!(account: account, contact: conversation.contact, inbox: inbox, title: 'Retorno', due_at: 1.hour.from_now)
    consentimento = WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                                    versao_aviso: 'v1', texto_aviso: 'Aviso.')
    linha = described_class.create!(account: account, inbox: inbox, message: message, crm_follow_up: follow_up,
                                    whatsapp_template_consent: consentimento, tipo: 'retorno', caminho: 'modelo', template_name: 'x',
                                    template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema')

    Message.where(id: message.id).delete_all
    Crm::FollowUp.where(id: follow_up.id).delete_all
    WhatsappTemplateConsent.where(id: consentimento.id).delete_all

    expect(described_class.find(linha.id)).to have_attributes(message_id: nil, crm_follow_up_id: nil, whatsapp_template_consent_id: nil,
                                                              tipo: 'retorno')
  end

  describe 'referências de outra conta são recusadas' do
    let(:outra) { create(:inbox) }
    let(:conversa_alheia) { create(:conversation, account: outra.account, inbox: outra) }

    def linha(**referencias)
      described_class.new(account: inbox.account, inbox: inbox, tipo: 'retorno', caminho: 'modelo', template_name: 'x',
                          template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema', **referencias)
    end

    it 'caixa' do
      expect(linha(inbox: outra).tap(&:valid?).errors.attribute_names).to eq([:inbox])
    end

    it 'mensagem' do
      mensagem = create(:message, account: outra.account, inbox: outra, conversation: conversa_alheia)

      expect(linha(message: mensagem).tap(&:valid?).errors.attribute_names).to eq([:message])
    end

    it 'follow-up' do
      follow_up = Crm::FollowUp.create!(account: outra.account, contact: conversa_alheia.contact, inbox: outra, title: 'Retorno',
                                        due_at: 1.hour.from_now)

      expect(linha(crm_follow_up: follow_up).tap(&:valid?).errors.attribute_names).to eq([:crm_follow_up])
    end

    it 'autorização' do
      consentimento = WhatsappTemplateConsent.create!(account: outra.account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU,
                                                      versao_aviso: 'v1', texto_aviso: 'Aviso.')

      expect(linha(whatsapp_template_consent: consentimento).tap(&:valid?).errors.attribute_names).to eq([:whatsapp_template_consent])
    end
  end
end

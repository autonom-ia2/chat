require 'rails_helper'

# Registro append-only de cada envio fora da janela (#1585): linha gravada não muda nem sai, nem pelo app nem pelo banco,
# e fica guardada mesmo com a conta, a caixa ou a mensagem apagadas.
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

  describe 'o banco recusa mudar ou apagar (gatilho, Rodrigo 15/10: "trava no banco")' do
    def sql_cru(comando)
      described_class.transaction(requires_new: true) { described_class.connection.execute(comando) }
    end

    it 'UPDATE, DELETE e TRUNCATE por SQL cru' do
      linha = gravar

      expect { sql_cru("UPDATE whatsapp_out_of_window_sends SET tipo = 'retorno' WHERE id = #{linha.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, UPDATE recusado/)
      expect { sql_cru("DELETE FROM whatsapp_out_of_window_sends WHERE id = #{linha.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, DELETE recusado/)
      expect { sql_cru('TRUNCATE whatsapp_out_of_window_sends') }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, TRUNCATE recusado/)
      expect(described_class.find(linha.id)).to have_attributes(tipo: 'andamento')
    end

    it 'delete_all e update_all do app também' do
      linha = gravar

      expect { described_class.transaction(requires_new: true) { described_class.where(id: linha.id).delete_all } }
        .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      expect { described_class.transaction(requires_new: true) { described_class.where(id: linha.id).update_all(tipo: 'x') } } # rubocop:disable Rails/SkipsModelValidations
        .to raise_error(ActiveRecord::StatementInvalid, /append-only/)
      expect(described_class.find(linha.id)).to have_attributes(tipo: 'andamento')
    end
  end

  describe 'guardado mesmo com a origem apagada (sem chave estrangeira)' do
    let(:account) { inbox.account }
    let(:conversation) { create(:conversation, account: account, inbox: inbox) }
    let(:message) { create(:message, account: account, inbox: inbox, conversation: conversation) }
    let(:follow_up) do
      Crm::FollowUp.create!(account: account, contact: conversation.contact, inbox: inbox, title: 'Retorno', due_at: 1.hour.from_now)
    end
    let(:consentimento) do
      WhatsappTemplateConsent.create!(account: account, marca: 'utility', acao: WhatsappTemplateConsent::LIGOU, versao_aviso: 'v1',
                                      texto_aviso: 'Aviso.')
    end
    let!(:linha) do
      described_class.create!(account: account, inbox: inbox, message: message, crm_follow_up: follow_up,
                              whatsapp_template_consent: consentimento, tipo: 'retorno', caminho: 'modelo', template_name: 'x',
                              template_language: 'pt_BR', categoria: 'UTILITY', origem: 'sistema')
    end
    let(:ids_de_origem) do
      { account_id: account.id, inbox_id: inbox.id, message_id: message.id, crm_follow_up_id: follow_up.id,
        whatsapp_template_consent_id: consentimento.id, tipo: 'retorno' }
    end

    it 'mensagem e follow-up apagados pelo Chatwoot: a linha fica, com os ids de origem' do
      expect { message.destroy! }.not_to raise_error
      expect { follow_up.destroy! }.not_to raise_error

      expect(described_class.find(linha.id)).to have_attributes(ids_de_origem)
      expect(described_class.find(linha.id).message).to be_nil
    end

    it 'caixa apagada pelo Chatwoot: a linha fica' do
      expect { inbox.destroy! }.not_to raise_error

      expect(described_class.find(linha.id)).to have_attributes(ids_de_origem)
    end

    # O follow-up sai antes: a FK de crm_follow_ups para accounts (do fork, sem cascade) recusaria apagar a conta, e
    # isso não tem a ver com esta tabela.
    it 'conta apagada pelo Chatwoot: a linha fica' do
      follow_up.destroy!

      expect { account.destroy! }.not_to raise_error

      expect(described_class.find(linha.id)).to have_attributes(ids_de_origem)
    end

    it 'follow-up, mensagem, caixa e conta apagados direto no banco (sem callbacks): a linha fica' do
      Crm::FollowUp.where(id: follow_up.id).delete_all
      Message.where(id: message.id).delete_all
      Inbox.where(id: inbox.id).delete_all
      Account.where(id: account.id).delete_all

      expect(described_class.find(linha.id)).to have_attributes(ids_de_origem)
    end
  end

  it 'na criação, referência informada precisa existir (sem FK, o banco não confere)' do
    nova = described_class.new(account: inbox.account, inbox: inbox, message_id: 0, crm_follow_up_id: 0, whatsapp_template_consent_id: 0,
                               tipo: 'retorno', caminho: 'modelo', template_name: 'x', template_language: 'pt_BR',
                               categoria: 'UTILITY', origem: 'sistema')

    expect(nova).not_to be_valid
    expect(nova.errors.attribute_names).to contain_exactly(:message, :crm_follow_up, :whatsapp_template_consent)
  end

  it 'na criação, conta e caixa são obrigatórias' do
    nova = described_class.new(tipo: 'retorno', caminho: 'modelo', template_name: 'x', template_language: 'pt_BR',
                               categoria: 'UTILITY', origem: 'sistema')

    expect(nova).not_to be_valid
    expect(nova.errors.attribute_names).to contain_exactly(:account, :inbox)
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

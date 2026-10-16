require 'rails_helper'

# Registro append-only da autorização do dono para o sistema criar modelos (#1586): linha gravada não muda nem sai, nem
# pelo app nem pelo banco, e fica guardada mesmo com a conta ou o usuário apagados.
RSpec.describe WhatsappTemplateConsent do
  let(:account) { create(:account) }

  def gravar(marca: 'utility', acao: described_class::LIGOU, conta: account)
    described_class.create!(account: conta, marca: marca, acao: acao, versao_aviso: 'v1', texto_aviso: 'Aviso.',
                            precos: { 'BRL' => '0.0350' })
  end

  it 'linha gravada não muda: update, update_columns e destroy são recusados' do
    linha = gravar

    expect { linha.update!(acao: described_class::DESLIGOU) }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect { linha.update_columns(acao: described_class::DESLIGOU) }.to raise_error(ActiveRecord::ReadOnlyRecord) # rubocop:disable Rails/SkipsModelValidations
    expect { linha.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    expect(described_class.find(linha.id)).to have_attributes(acao: described_class::LIGOU, texto_aviso: 'Aviso.')
  end

  it 'só aceita as duas marcas e as duas ações, com versão e texto' do
    linha = described_class.new(account: account, marca: 'propaganda', acao: 'ligar', versao_aviso: '', texto_aviso: '')

    expect(linha).not_to be_valid
    expect(linha.errors.attribute_names).to include(:marca, :acao, :versao_aviso, :texto_aviso)
  end

  describe '.ativo?' do
    it 'sem linha: desligada' do
      expect(described_class.ativo?(account, :utility)).to be(false)
    end

    it 'vale a última linha da conta e da marca' do
      gravar
      expect(described_class.ativo?(account, :utility)).to be(true)
      expect(described_class.ativo?(account, :marketing)).to be(false)

      gravar(acao: described_class::DESLIGOU)
      expect(described_class.ativo?(account, :utility)).to be(false)
    end

    it 'a linha de outra conta não conta' do
      gravar(conta: create(:account))

      expect(described_class.ativo?(account, :utility)).to be(false)
    end

    it 'duas linhas no mesmo instante: vale a gravada por último' do
      agora = Time.zone.parse('2026-10-15 12:00:00')
      travel_to(agora) do
        gravar
        gravar(acao: described_class::DESLIGOU)
      end

      expect(described_class.ativo?(account, 'utility')).to be(false)
    end
  end

  it 'assinante do evento que falha não desfaz nem esconde a linha gravada' do
    assinatura = ActiveSupport::Notifications.subscribe(described_class::EVENTO_LIGADO) { raise ArgumentError, 'assinante' }
    allow(Rails.logger).to receive(:error)

    expect { gravar }.not_to raise_error

    expect(described_class.ativo?(account, :utility)).to be(true)
    expect(Rails.logger).to have_received(:error).with(include('evento_falhou', 'ArgumentError'))
  ensure
    ActiveSupport::Notifications.unsubscribe(assinatura)
  end

  it 'grava o nome de quem mudou (user_name); sem usuário, fica vazio' do
    user = create(:user, account: account, name: 'Ana Souza')

    com_usuario = described_class.create!(account: account, user: user, marca: 'utility', acao: described_class::LIGOU,
                                          versao_aviso: 'v1', texto_aviso: 'Aviso.')

    expect(com_usuario.reload.user_name).to eq('Ana Souza')
    expect(gravar.reload.user_name).to be_nil
  end

  it 'na criação, quem mudou precisa ser usuário da conta (sem FK, quem confere é o model)' do
    de_fora = create(:user, account: create(:account))
    linha = described_class.new(account: account, user: de_fora, marca: 'utility', acao: described_class::LIGOU, versao_aviso: 'v1',
                                texto_aviso: 'Aviso.')

    expect(linha).not_to be_valid
    expect(linha.errors.attribute_names).to eq([:user])
  end

  it 'na criação, a conta é obrigatória' do
    linha = described_class.new(marca: 'utility', acao: described_class::LIGOU, versao_aviso: 'v1', texto_aviso: 'Aviso.')

    expect(linha).not_to be_valid
    expect(linha.errors.attribute_names).to eq([:account])
  end

  describe 'o banco recusa mudar ou apagar (gatilho, Rodrigo 15/10: "trava no banco")' do
    def sql_cru(comando)
      described_class.transaction(requires_new: true) { described_class.connection.execute(comando) }
    end

    it 'UPDATE, DELETE e TRUNCATE por SQL cru' do
      linha = gravar

      expect { sql_cru("UPDATE whatsapp_template_consents SET acao = 'desligou' WHERE id = #{linha.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, UPDATE recusado/)
      expect { sql_cru("DELETE FROM whatsapp_template_consents WHERE id = #{linha.id}") }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, DELETE recusado/)
      expect { sql_cru('TRUNCATE whatsapp_template_consents') }
        .to raise_error(ActiveRecord::StatementInvalid, /registro append-only, TRUNCATE recusado/)
      expect(described_class.find(linha.id)).to have_attributes(acao: described_class::LIGOU)
    end
  end

  describe 'guardado mesmo com a origem apagada (sem chave estrangeira)' do
    let(:user) { create(:user, account: account, name: 'Ana Souza') }
    let!(:linha) do
      described_class.create!(account: account, user: user, marca: 'utility', acao: described_class::LIGOU, versao_aviso: 'v1',
                              texto_aviso: 'Aviso.')
    end
    let(:guardada) { { account_id: account.id, user_id: user.id, user_name: 'Ana Souza', acao: described_class::LIGOU } }

    it 'usuário apagado pelo Chatwoot: a linha fica, com o id e o nome' do
      expect { user.destroy! }.not_to raise_error

      expect(described_class.find(linha.id)).to have_attributes(guardada)
      expect(described_class.find(linha.id).user).to be_nil
    end

    it 'conta apagada pelo Chatwoot: a linha fica, e ativo?/ultima seguem pelo account_id' do
      expect { account.destroy! }.not_to raise_error

      expect(described_class.find(linha.id)).to have_attributes(guardada)
      expect(described_class.ultima(account, :utility)).to eq(linha)
      expect(described_class.ativo?(account, :utility)).to be(true)
    end

    it 'conta e usuário apagados direto no banco (sem callbacks): a linha fica' do
      AccountUser.where(user_id: user.id).delete_all
      User.where(id: user.id).delete_all
      Account.where(id: account.id).delete_all

      expect(described_class.find(linha.id)).to have_attributes(guardada)
    end
  end
end

require 'rails_helper'

# Registro append-only da autorização do dono para o sistema criar modelos (#1586): linha gravada não muda nem sai.
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

  it 'usuário apagado não apaga o registro' do
    user = create(:user, account: account)
    linha = described_class.create!(account: account, user: user, marca: 'utility', acao: described_class::LIGOU,
                                    versao_aviso: 'v1', texto_aviso: 'Aviso.')

    user.destroy!

    expect(described_class.find(linha.id).user_id).to be_nil
  end
end

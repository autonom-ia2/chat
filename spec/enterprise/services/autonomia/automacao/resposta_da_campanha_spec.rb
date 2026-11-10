require 'rails_helper'

# Lote 5 (#2681): o filtro "respondeu à campanha" lê o nome da última campanha que o contato recebeu nesta caixa antes
# da mensagem. Em spec/enterprise: o destinatário da campanha (CampaignRecipient) é do EE.
RSpec.describe Autonomia::Automacao::RespostaDaCampanha do
  let(:canal) { create(:channel_whatsapp, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:account) { canal.account }
  let(:inbox) { canal.inbox }
  let(:ana) { create(:contact, account: account, phone_number: '+5511900000061') }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, contact: ana) }

  def recebeu(titulo, quando, caixa: inbox, status: :sent)
    campanha = create(:campaign, account: account, inbox: caixa, title: titulo)
    CampaignRecipient.create!(account: account, campaign: campanha, contact: ana, inbox: caixa, status: status,
                              sent_at: (quando unless status == :failed))
  end

  def escreve(quando, tipo: :incoming)
    travel_to(quando) { create(:message, account: account, inbox: inbox, conversation: conversa, message_type: tipo) }
  end

  it 'é o nome da última campanha recebida antes da mensagem' do
    recebeu('Pré-Black', 3.days.ago)
    recebeu('Últimas horas', 1.day.ago)

    expect(described_class.titulo(escreve(2.days.ago))).to eq('Pré-Black')
    expect(described_class.titulo(escreve(1.hour.ago))).to eq('Últimas horas')
  end

  it 'campanha que falhou, de outra caixa ou depois da mensagem não conta' do
    recebeu('Falhou', 3.days.ago, status: :failed)
    recebeu('Outra caixa', 3.days.ago, caixa: create(:inbox, account: account))
    recebeu('Depois', 1.minute.from_now)

    expect(described_class.titulo(escreve(Time.current))).to be_nil
  end

  # 🟡 da qualidade (#2686): a próxima campanha recebida na caixa fecha a janela da anterior. No filtro do gatilho,
  # "respondeu à Pré-Black" deixa de casar com a mensagem que chega depois da 2ª campanha.
  it 'a mensagem depois da 2ª campanha não casa mais com a 1ª no filtro', :aggregate_failures do
    recebeu('Pré-Black', 3.days.ago)
    recebeu('Últimas horas', 1.day.ago)
    casa = lambda do |mensagem|
      valor = Autonomia::Automacao::Valores.new(alvo: conversa, mensagem: mensagem, quem: nil).ler('mensagem.campanha')
      valor == 'Pré-Black'
    end

    expect(casa.call(escreve(2.days.ago))).to be(true)
    expect(casa.call(escreve(1.hour.ago))).to be(false)
  end

  it 'a campanha de outra caixa não fecha a janela da anterior' do
    recebeu('Pré-Black', 3.days.ago)
    recebeu('Outra caixa', 1.day.ago, caixa: create(:inbox, account: account))

    expect(described_class.titulo(escreve(1.hour.ago))).to eq('Pré-Black')
  end

  it 'só a mensagem do cliente responde' do
    recebeu('Pré-Black', 1.day.ago)

    expect(described_class.titulo(escreve(Time.current, tipo: :outgoing))).to be_nil
  end
end

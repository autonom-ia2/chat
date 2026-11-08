require 'rails_helper'

describe ConversaCanal::CopiaEncaminhada do
  let(:conversation) { create(:conversation) }
  let(:prefixo) { Waha::EcoDoCelular::PREFIXO }

  def mensagem(content, atributos = {})
    create(:message, conversation: conversation, account: conversation.account, inbox: conversation.inbox,
                     message_type: :outgoing, content: content, content_attributes: atributos)
  end

  it 'o eco antigo do celular vai sem o prefixo do conector (#1941)' do
    eco = mensagem("#{prefixo}\n\nOi, tudo bem?", external_echo: true)

    expect(described_class.new(eco).envios.first[:content]).to eq('Oi, tudo bem?')
  end

  it 'o eco que era só o prefixo não vira mensagem vazia' do
    eco = mensagem(prefixo, external_echo: true)

    expect(described_class.new(eco).envios).to eq([])
  end

  it 'mensagem do painel que começa igual ao prefixo vai inteira' do
    painel = mensagem("#{prefixo}\n\nTexto do painel")

    expect(described_class.new(painel).envios.first[:content]).to eq("#{prefixo}\n\nTexto do painel")
  end

  it 'eco sem o prefixo vai como está' do
    eco = mensagem('Resposta pelo celular', external_echo: true)

    expect(described_class.new(eco).envios.first[:content]).to eq('Resposta pelo celular')
  end
end

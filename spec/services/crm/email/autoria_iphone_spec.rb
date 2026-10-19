require 'rails_helper'

# #1869: produção, conta 1, conversa 320, mensagem 19511. Resposta pelo Mail do iPhone com o histórico em texto puro
# (linhas com ">" e ">>", sem <blockquote>), precedido pelo cabeçalho pt-BR do iPhone. O corte para a IA e para o
# #1813 tem de sair sem o histórico.
RSpec.describe Crm::Email::Autoria do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_email, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: create(:contact, account: account)) }

  let(:iphone) do
    <<~TEXTO
      RV


      Enviado do meu iPhone 14 Pro

      Em 19 de out. de 2026, à(s) 07:51, Fulano <fulano@example.com> escreveu:

      > Segue a proposta revisada.
      >
      >> Em 18 de out. de 2026, à(s) 18:02, Ana <ana@example.com> escreveu:
      >>
      >> Pode mandar de novo?
    TEXTO
  end

  def email!(content)
    create(:message, account: account, inbox: channel.inbox, conversation: conversation, sender: conversation.contact,
                     message_type: :incoming, content_type: :incoming_email, content: content,
                     content_attributes: { 'email' => { 'text_content' => { 'full' => content } } })
  end

  it 'iPhone pt-BR em texto puro: fica o texto novo e a assinatura, sem o cabeçalho e sem as linhas citadas',
     :aggregate_failures do
    texto = described_class.texto_novo(email!(iphone))

    expect(texto).to eq("RV\n\n\nEnviado do meu iPhone 14 Pro")
    expect(texto).not_to include('escreveu')
    expect(texto).not_to include('proposta')
    expect(Crm::Email::BlocoCitado.sem(iphone)).to eq(texto)
  end

  it 'iPhone pt-BR só com o histórico: sem corte com sem_fallback, o texto inteiro por padrão', :aggregate_failures do
    so_citado = iphone.lines.drop(5).join
    message = email!(so_citado)

    expect(described_class.texto_novo(message, sem_fallback: true)).to be_nil
    expect(described_class.texto_novo(message)).to eq(so_citado)
  end
end

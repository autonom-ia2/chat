require 'rails_helper'

# #1786: histórico e encaminhado da resposta de e-mail, montados no servidor com o original formatado.
RSpec.describe ConversaCanal::CitacaoDoEmail do
  let(:account) { create(:account, locale: 'pt_BR') }
  let(:channel) { create(:channel_email, account: account) }
  let(:inbox) { channel.inbox }
  let(:contato) { create(:contact, account: account, name: 'Marina Costa', email: 'marina@exemplo.com.br') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contato) }
  let(:user) { create(:user, account: account) }
  let!(:original) do
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, sender: contato,
                     content: 'Segue a lista', created_at: Time.zone.parse('2026-10-17 13:15:00 UTC'),
                     content_attributes: { email: {
                       from: ['marina@exemplo.com.br'], to: ['comercial@loja.com.br'], subject: 'Proposta',
                       html_content: { full: '<p>Segue a <b>lista</b>:</p><ul><li>incêndio</li></ul><script>alert(1)</script>' },
                       text_content: { full: "Segue a lista:\n- incêndio" }
                     } })
  end

  def responder(tipo, message_id = original.id)
    Messages::MessageBuilder.new(user, conversation, {
                                   content: 'Oi, Marina!',
                                   content_attributes: { email_citacao: { tipo: tipo, message_id: message_id } }
                                 }).perform
  end

  it 'histórico: o texto do atendente, a atribuição em português no fuso da conta e o original formatado' do
    with_modified_env(CRM_DEFAULT_TIMEZONE: 'America/Sao_Paulo') do
      html = responder('historico').content_attributes.dig('email', 'html_content', 'reply')

      expect(html).to include('Oi, Marina!')
      expect(html).to include('Em sáb., 17 de out. de 2026 às 10:15, Marina Costa &lt;marina@exemplo.com.br&gt; escreveu:')
      expect(html).to include('<blockquote class="gmail_quote"')
      expect(html).to include('<b>lista</b>', '<li>incêndio</li>')
      expect(html).not_to include('<script')
    end
  end

  it 'encaminhado: o bloco "Mensagem encaminhada" com De, Assunto e Para, e o original' do
    mensagem = responder('encaminhado')
    html = mensagem.content_attributes.dig('email', 'html_content', 'reply')
    texto = mensagem.content_attributes.dig('email', 'text_content', 'reply')

    expect(html).to include('---------- Mensagem encaminhada ----------', 'Assunto: Proposta', 'Para: comercial@loja.com.br')
    expect(html).to include('<li>incêndio</li>')
    expect(texto).to include('Mensagem encaminhada', "Segue a lista:\n- incêndio")
  end

  it 'o content continua só com o que o atendente escreveu (o CRM e a IA leem só isso)' do
    expect(responder('historico').content).to eq('Oi, Marina!')
  end

  it 'mensagem de outra conversa ou privada não é citada' do
    outra = create(:message, account: account, inbox: inbox, conversation: create(:conversation, account: account, inbox: inbox),
                             message_type: :incoming, content: 'segredo de outro cliente')
    nota = create(:message, account: account, inbox: inbox, conversation: conversation, private: true, content: 'nota')

    [outra, nota].each do |mensagem|
      html = responder('historico', mensagem.id).content_attributes.dig('email', 'html_content', 'reply')
      expect(html).not_to include('gmail_quote')
      expect(html).not_to include(mensagem.content)
    end
  end

  it 'tipo desconhecido ou sem pedido: o e-mail sai como antes' do
    html = responder('qualquer').content_attributes.dig('email', 'html_content', 'reply')
    expect(html).not_to include('gmail_quote')

    sem = Messages::MessageBuilder.new(user, conversation, { content: 'Oi' }).perform
    expect(sem.content_attributes.dig('email', 'html_content', 'reply')).not_to include('gmail_quote')
  end
end

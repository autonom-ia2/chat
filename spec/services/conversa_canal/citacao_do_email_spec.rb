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

  before { account.enable_features!('conversa_email_nova') }

  def responder(tipo, message_id = original.id, to_emails: nil)
    parametros = { content: 'Oi, Marina!', content_attributes: { email_citacao: { tipo: tipo, message_id: message_id } } }
    parametros[:to_emails] = to_emails if to_emails
    Messages::MessageBuilder.new(user, conversation, parametros).perform
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
    mensagem = responder('encaminhado', to_emails: 'juridico@loja.com.br')
    html = mensagem.content_attributes.dig('email', 'html_content', 'reply')
    texto = mensagem.content_attributes.dig('email', 'text_content', 'reply')

    expect(html).to include('---------- Mensagem encaminhada ----------', 'Assunto: Proposta', 'Para: comercial@loja.com.br')
    expect(html).to include('<li>incêndio</li>')
    expect(texto).to include('Mensagem encaminhada', "Segue a lista:\n- incêndio")
  end

  it 'encaminhar sem Para é recusado (iria para o próprio cliente) e nada é gravado' do
    expect { responder('encaminhado') }.to raise_error(ArgumentError, I18n.t('conversa_canal.email.encaminhar_sem_para'))
      .and(not_change { conversation.messages.count })
  end

  describe 'encaminhado no envio' do
    before do
      anexo = original.attachments.new(account_id: account.id, file_type: :file)
      anexo.file.attach(io: Rails.root.join('spec/assets/avatar.png').open, filename: 'cotacao.png', content_type: 'image/png')
      anexo.save!
      conversation.update!(additional_attributes: { mail_subject: 'Proposta' })
      mailer = ConversationReplyMailer.new
      allow(ConversationReplyMailer).to receive(:new).and_return(mailer)
      allow(mailer).to receive(:smtp_config_set_or_development?).and_return(true)
    end

    it 'leva os anexos do original, sai com "Enc:" e fora do fio do cliente' do
      mensagem = responder('encaminhado', to_emails: 'juridico@loja.com.br')
      email = ConversationReplyMailer.email_reply(mensagem).deliver_now

      expect(mensagem.attachments.map { |a| a.file.filename.to_s }).to eq(['cotacao.png'])
      expect(email.subject).to eq('Enc: Proposta')
      expect(email.to).to eq(['juridico@loja.com.br'])
      expect(email.in_reply_to).to be_nil
      expect(email.references).to be_nil
      expect(email.attachments.map(&:filename)).to include('cotacao.png')
    end

    it 'o histórico continua como resposta do fio (Re: e In-Reply-To)' do
      original.update!(content_attributes: original.content_attributes.merge('email' => original.content_attributes['email']
                                                                                  .merge('message_id' => 'abc@cliente.com')))
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'antes')
      email = ConversationReplyMailer.email_reply(responder('historico')).deliver_now

      expect(email.subject).to eq('Re: Proposta')
      expect(email.in_reply_to).to eq('abc@cliente.com')
    end
  end

  it 'citar um e-mail que saiu: o endereço da caixa, nunca o e-mail de login do atendente' do
    atendente = create(:user, account: account, name: 'João Lima', email: 'joao.pessoal@gmail.com')
    enviado = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing,
                               sender: atendente, content: 'Proposta enviada')

    html = responder('historico', enviado.id).content_attributes.dig('email', 'html_content', 'reply')

    expect(html).to include("#{atendente.available_name} &lt;#{channel.email}&gt; escreveu:")
    expect(html).not_to include('joao.pessoal@gmail.com')
  end

  it 'com a chave conversa_email_nova desligada, o pedido de citação é ignorado' do
    account.disable_features!('conversa_email_nova')

    expect(responder('historico').content_attributes.dig('email', 'html_content', 'reply')).not_to include('gmail_quote')
  end

  it 'e-mail do Outlook: o CSS, o título e o script do original não aparecem na citação, só o corpo' do
    outlook = <<~HTML
      <html xmlns:o="urn:schemas-microsoft-com:office:office"><head><meta http-equiv="Content-Type" content="text/html; charset=utf-8">
      <title>Proposta da Marina</title><style><!-- /* Font Definitions */ @font-face {font-family:"Cambria Math";}
      p.MsoNormal {margin:0cm;} --></style><!--[if gte mso 9]><xml><o:shapedefaults v:ext="edit" spidmax="1026" /></xml><![endif]-->
      </head><body lang="PT-BR"><div class="WordSection1"><p class="MsoNormal">Segue a <b>cotação</b> anexa.</p></div>
      <script>alert(1)</script></body></html>
    HTML
    original.update!(content_attributes: { email: { from: ['marina@exemplo.com.br'], html_content: { full: outlook } } })

    html = responder('historico').content_attributes.dig('email', 'html_content', 'reply')

    expect(html).to include('Segue a <b>cotação</b> anexa.')
    expect(html).not_to include('Font Definitions', '@font-face', 'MsoNormal {', 'Proposta da Marina', 'alert(1)', 'shapedefaults')
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

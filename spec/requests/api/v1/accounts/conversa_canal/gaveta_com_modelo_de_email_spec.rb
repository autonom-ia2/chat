require 'rails_helper'

# #1809: a gaveta "Escrever" cria a conversa com a primeira mensagem (ConversationsController#create →
# Messages::MessageBuilder). Com o modelo de e-mail, o pedido vai em `message[content_attributes]` (JSON, como no
# FormData da gaveta) e o mesmo prepend da resposta (ConversaCanal::MessageBuilderComCitacao) monta e limpa o HTML.
RSpec.describe 'Gaveta Escrever com modelo de e-mail' do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:contato) { create(:contact, account: account, name: 'Marina Costa', email: 'marina@exemplo.com.br') }
  let(:modelo) { EmailCampaignTemplate.create!(account: account, name: 'Proposta', body_html: '<p>x</p>') }
  let(:html_do_navegador) do
    '<html><head><style>.a{color:red}</style></head><body><p onclick="roubar()">Olá, Marina Costa! Cotação COT-4817.</p>' \
      '<script>alert(1)</script><div class="footer-locked">Sair da lista</div></body></html>'
  end

  before { create(:inbox_member, user: agent, inbox: inbox) }

  def criar(pedido, conteudo: 'Segue a proposta.')
    post "/api/v1/accounts/#{account.id}/conversations",
         params: { inbox_id: inbox.id, contact_id: contato.id, additional_attributes: { mail_subject: 'Sua proposta' },
                   message: { content: conteudo, content_attributes: pedido.to_json } },
         headers: agent.create_new_auth_token
  end

  it 'cria a conversa com o texto em cima e o modelo, sem rodapé de descadastro, sem script e sem evento' do
    criar({ email_modelo: { template_id: modelo.id, html: html_do_navegador, so_modelo: false } })

    expect(response).to have_http_status(:ok)
    mensagem = Conversation.find_by!(display_id: response.parsed_body['id'], account: account).messages.last
    html = mensagem.content_attributes.dig('email', 'html_content', 'full')
    expect(html).to include('Olá, Marina Costa! Cotação COT-4817.')
    expect(html.index('Segue a proposta.')).to be < html.index('Olá, Marina Costa!')
    expect(html).not_to include('Sair da lista')
    expect(html).not_to include('footer-locked')
    expect(html).not_to include('<script')
    expect(html).not_to include('onclick')
  end

  it 'guarda o texto do atendente, o assunto da gaveta e só qual modelo foi usado' do
    criar({ email_modelo: { template_id: modelo.id, html: html_do_navegador, so_modelo: false } })

    mensagem = Conversation.find_by!(display_id: response.parsed_body['id'], account: account).messages.last
    expect(mensagem.content).to eq('Segue a proposta.')
    expect(mensagem.conversation.additional_attributes['mail_subject']).to eq('Sua proposta')
    # O HTML grande não fica guardado de novo no pedido: só qual modelo foi usado.
    expect(mensagem.content_attributes['email_modelo']).to eq('template_id' => modelo.id, 'so_modelo' => false)
  end

  it 'só o modelo: o corpo é o modelo, sem o bloco de texto do atendente' do
    criar({ email_modelo: { template_id: modelo.id, html: html_do_navegador, so_modelo: true } },
          conteudo: 'Olá, Marina Costa! Cotação COT-4817.')

    mensagem = Conversation.find_by!(display_id: response.parsed_body['id'], account: account).messages.last
    html = mensagem.content_attributes.dig('email', 'html_content', 'full')
    expect(html.scan('Olá, Marina Costa!').size).to eq(1)
    expect(html).not_to include('Sair da lista')
  end

  it 'modelo de outra conta: ignora o HTML recebido e o e-mail sai só com o texto' do
    de_fora = EmailCampaignTemplate.create!(account: create(:account), name: 'Alheio', body_html: '<p>y</p>')
    criar({ email_modelo: { template_id: de_fora.id, html: html_do_navegador, so_modelo: false } })

    mensagem = Conversation.find_by!(display_id: response.parsed_body['id'], account: account).messages.last
    html = mensagem.content_attributes.dig('email', 'html_content', 'full')
    expect(html).to include('Segue a proposta.')
    expect(html).not_to include('Cotação COT-4817')
  end
end

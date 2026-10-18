require 'rails_helper'

# #1786: modelo de e-mail das Campanhas na resposta: campos preenchidos pelo contato, pela IA ou vazios; e o e-mail
# montado com o texto do atendente em cima, o modelo no meio e o histórico no fim, sem rodapé de descadastro.
RSpec.describe ConversaCanal::ModeloDeEmail do
  let(:account) { create(:account) }
  let(:inbox) { create(:channel_email, account: account).inbox }
  let(:contato) do
    create(:contact, account: account, name: 'Marina Costa', email: 'marina@exemplo.com.br',
                     custom_attributes: { 'plano' => 'Empresarial' })
  end
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contato) }
  let(:user) { create(:user, account: account, name: 'Ana Souza') }
  let(:mjml) do
    '<mjml><mj-body><mj-section><mj-column><mj-text>Olá, {{ contact.first_name }}! Plano {{ plano }}, ' \
      'cotação {{ numero_da_cotacao }}, cidade {{ cidade | default: "SP" }}. {{ agent.name }}</mj-text></mj-column>' \
      '</mj-section><mj-section css-class="footer-locked"><mj-column><mj-text>{{ unsubscribe_url }}</mj-text>' \
      '</mj-column></mj-section></mj-body></mjml>'
  end
  let(:modelo) { EmailCampaignTemplate.create!(account: account, name: 'Proposta', body_mjml: mjml, body_html: '<p>x</p>') }
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before do
    allow(Crm::Ai::ResponsesClient).to receive(:new).and_return(cliente)
  end

  def campos(com_ia:)
    allow(Crm::Ai::CredentialResolver).to receive(:new).and_return(
      instance_double(Crm::Ai::CredentialResolver, configured?: com_ia, resolve: { api_key: 'k', api_base: 'https://api.openai.com' })
    )
    described_class.new(modelo: modelo, conversation: conversation, user: user).como_json[:campos]
  end

  it 'lê as variáveis na ordem, sem repetir, sem filtro e sem o unsubscribe_url' do
    expect(described_class.chaves(mjml)).to eq(%w[contact.first_name plano numero_da_cotacao cidade agent.name])
  end

  it 'preenche pelo contato e pela conta; sem IA o resto fica vazio para o atendente' do
    expect(campos(com_ia: false)).to eq([
                                          { chave: 'contact.first_name', valor: 'Marina', origem: 'contato' },
                                          { chave: 'plano', valor: 'Empresarial', origem: 'contato' },
                                          { chave: 'numero_da_cotacao', valor: '', origem: 'vazio' },
                                          { chave: 'cidade', valor: '', origem: 'vazio' },
                                          { chave: 'agent.name', valor: 'Ana Souza', origem: 'contato' }
                                        ])
  end

  it 'com IA, pede só o que faltou e marca a origem' do
    allow(cliente).to receive(:create).and_return(
      text: { campos: [{ chave: 'numero_da_cotacao', valor: 'COT-4817' }, { chave: 'cidade', valor: '' }] }.to_json
    )

    resultado = campos(com_ia: true)

    expect(resultado.find { |c| c[:chave] == 'numero_da_cotacao' }).to eq(chave: 'numero_da_cotacao', valor: 'COT-4817', origem: 'ia')
    expect(resultado.find { |c| c[:chave] == 'cidade' }).to eq(chave: 'cidade', valor: '', origem: 'vazio')
    expect(cliente).to have_received(:create) do |argumentos|
      expect(JSON.parse(argumentos[:input])['chaves']).to eq(%w[numero_da_cotacao cidade])
    end
  end

  describe 'na resposta enviada' do
    let(:html_do_modelo) do
      '<html><head><style>.x{color:red}</style></head><body><div class="corpo">Modelo para Marina</div>' \
        '<script>alert(1)</script><img src="https://loja.com/email_campaigns/t/o/abc"><a href="#" onclick="x()">link</a>' \
        '<div class="footer-locked">Sair da lista</div></body></html>'
    end

    def responder(conteudo, modelo_id: modelo.id, so_modelo: false, citacao: nil)
      atributos = { email_modelo: { template_id: modelo_id, html: html_do_modelo, so_modelo: so_modelo } }
      atributos[:email_citacao] = citacao if citacao
      Messages::MessageBuilder.new(user, conversation, { content: conteudo, content_attributes: atributos }).perform
    end

    it 'texto do atendente em cima do modelo, com o head do modelo e sem script, rastreio, on* e rodapé' do
      mensagem = responder('Oi, Marina! Segue a proposta.')
      html = mensagem.content_attributes.dig('email', 'html_content', 'reply')

      expect(html.index('Oi, Marina!')).to be < html.index('Modelo para Marina')
      expect(html).to include('.x{color:red}')
      expect(html).not_to include('alert(1)', 'email_campaigns/t/', 'onclick', 'Sair da lista')
      texto = mensagem.content_attributes.dig('email', 'text_content', 'reply')
      expect(texto).to include('Modelo para Marina')
      expect(texto.scan('Oi, Marina!').size).to eq(1)
    end

    it 'não guarda o HTML do modelo de novo no pedido' do
      mensagem = responder('Oi')

      expect(mensagem.content_attributes['email_modelo']).to eq('template_id' => modelo.id, 'so_modelo' => false)
    end

    it 'só o modelo: o texto que veio no conteúdo não entra de novo no corpo' do
      html = responder('Modelo para Marina', so_modelo: true).content_attributes.dig('email', 'html_content', 'reply')

      expect(html.scan('Modelo para Marina').size).to eq(1)
    end

    it 'histórico vai depois do modelo' do
      anterior = create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming,
                                  content: 'Pedido original', content_attributes: { email: { html_content: { full: '<p>Pedido original</p>' } } })
      html = responder('Oi', citacao: { tipo: 'historico', message_id: anterior.id })
             .content_attributes.dig('email', 'html_content', 'reply')

      expect(html.index('Modelo para Marina')).to be < html.index('Pedido original')
    end

    it 'link com o esquema quebrado por tab ou quebra de linha também sai' do
      atributos = { email_modelo: { template_id: modelo.id, so_modelo: false,
                                    html: '<body><p>Modelo para Marina</p><a href="java&#x09;script:alert(1)">a</a>' \
                                          '<a href=" JAVA&#x0A;SCRIPT:alert(2)">b</a><a href="https://loja.com">c</a></body>' } }
      html = Messages::MessageBuilder.new(user, conversation, { content: 'Oi', content_attributes: atributos })
                                     .perform.content_attributes.dig('email', 'html_content', 'reply')

      expect(html).not_to include('alert(1)', 'alert(2)')
      expect(html).to include('https://loja.com')
    end

    it 'modelo de outra conta é ignorado: sai só o texto' do
      outro = EmailCampaignTemplate.create!(account: create(:account), name: 'Alheio', body_html: '<p>x</p>')
      html = responder('Oi, só texto', modelo_id: outro.id).content_attributes.dig('email', 'html_content', 'reply')

      expect(html).to include('Oi, só texto')
      expect(html).not_to include('Modelo para Marina')
    end
  end
end

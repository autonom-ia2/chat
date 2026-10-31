require 'rails_helper'

# #1479 F1: opções e botão de link na resposta do agente. Quem pode receber o campo, o que o modelo pediu (conferido)
# e como sai em cada caixa.
RSpec.describe Autonomia::Agents::Interacao do
  let(:account) { conta_da_fase2 }
  let(:cloud) { create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false) }
  let(:inbox) { cloud.inbox }
  let(:contact_inbox) { create(:contact_inbox, inbox: inbox, source_id: '5511937016094') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact_inbox: contact_inbox) }
  let(:agent) { criar_principal(account) }
  let(:delivery) { instance_double(Autonomia::Agents::Tools::Delivery, conversation: conversation) }

  let(:tres) do
    [{ 'id' => 'manha', 'titulo' => 'Manhã', 'descricao' => nil }, { 'id' => 'tarde', 'titulo' => 'Tarde', 'descricao' => nil },
     { 'id' => 'noite', 'titulo' => 'Noite', 'descricao' => nil }]
  end
  let(:pedido) { { 'tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?', 'opcoes' => tres, 'botao' => nil, 'link' => nil } }
  let(:opcoes) { described_class.do_modelo(pedido, enderecos: Set.new) }
  let(:link) { pede_link(url, "veja #{url}") }
  let(:url) { 'https://exemplo.com.br/proposta?a=1&b=2' }
  let(:numerada) { "Temos vaga.\n\nQual período?\n\n1. Manhã\n2. Tarde\n3. Noite" }

  # Os endereços que o dono escreveu nestes textos.
  def donos(*textos)
    described_class::Enderecos.dos_textos(textos)
  end

  # O modelo pede um botão para `pedido`; o dono escreveu `textos`.
  def pede_link(pedido, *textos)
    described_class.do_modelo({ 'tipo' => 'link', 'link' => { 'rotulo' => 'Abrir proposta', 'url' => pedido } }, enderecos: donos(*textos))
  end

  def janela_aberta(conversa = conversation)
    create(:message, message_type: :incoming, content: 'oi', conversation: conversa, inbox: conversa.inbox, account: account)
  end

  def conversa_em(channel)
    create(:conversation, account: account, inbox: channel.inbox).tap { |conversa| janela_aberta(conversa) }
  end

  describe '.disponivel?' do
    it 'vale no atendimento ao cliente, com a Fase 2, numa caixa que leva o formato' do
      expect(described_class.disponivel?(agent: agent, delivery: delivery, audience: :customer)).to be(true)
    end

    it 'não vale com a Fase 2 desligada' do
      agente = criar_principal(conta_da_fase2(ligada: false))
      expect(described_class.disponivel?(agent: agente, delivery: delivery, audience: :customer)).to be(false)
    end

    it 'não vale sem contexto de entrega (Testar, copiloto, Guia)' do
      expect(described_class.disponivel?(agent: agent, delivery: nil, audience: :customer)).to be(false)
    end

    it 'não vale para o atendente' do
      expect(described_class.disponivel?(agent: agent, delivery: delivery, audience: :attendant)).to be(false)
    end

    it 'não vale para a Lia' do
      lia = instance_double(Autonomia::Agents::Agent, agent_type: 'insurance_quote', account: account)
      expect(described_class.disponivel?(agent: lia, delivery: delivery, audience: :customer)).to be(false)
    end

    it 'não vale no e-mail nem no chat do site; vale na caixa API' do
      email = conversa_em(create(:channel_email, account: account))
      widget = conversa_em(create(:channel_widget, account: account))
      api = conversa_em(create(:channel_api, account: account))
      resultado = [email, widget, api].map do |conversa|
        entrega = instance_double(Autonomia::Agents::Tools::Delivery, conversation: conversa)
        described_class.disponivel?(agent: agent, delivery: entrega, audience: :customer)
      end
      expect(resultado).to eq([false, false, true])
    end
  end

  describe 'INSTRUCAO' do
    it 'diz que a pergunta das opções não lista as alternativas, que vão nos botões' do
      expect(described_class::INSTRUCAO).to include('Ela NÃO lista as alternativas, porque elas vão nos botões ' \
                                                    '(ex.: "Qual período você prefere?").')
    end

    it 'mantém as regras do cabeçalho, do reply sem repetição e do link só com endereço escrito' do
      expect(described_class::INSTRUCAO).to include('`header`: SEMPRE um título curto do assunto',
                                                    'NÃO repita a pergunta nem as opções em `reply`',
                                                    'nunca invente nem monte endereço')
    end

    it 'link: só da instrução e da base (ou ferramenta dentro delas), nunca do cliente, e o reply não promete o botão' do
      expect(described_class::INSTRUCAO).to include('ESCRITO nas suas instruções ou na base de conhecimento',
                                                    'devolveu dentro de um desses endereços',
                                                    'Nunca um endereço que o cliente mandou',
                                                    'não fale do botão nele (nada de "toque no botão")',
                                                    '`reply` precisa fazer sentido sozinho se o botão não sair')
      expect(described_class::INSTRUCAO).not_to include('na conversa ou no resultado')
    end
  end

  describe '.do_modelo' do
    it 'ignora o que não é interação' do
      expect([nil, 'opcoes', { 'tipo' => 'mapa' }].map { |valor| described_class.do_modelo(valor, enderecos: Set.new) }).to all(be_nil)
    end

    it 'guarda as opções; sem texto do modelo, o botão da lista fica para a entrega' do
      expect(opcoes).to eq('tipo' => 'opcoes', 'header' => 'Agendamento', 'pergunta' => 'Qual período?', 'botao' => nil,
                           'opcoes' => [{ 'id' => 'manha', 'title' => 'Manhã', 'description' => nil },
                                        { 'id' => 'tarde', 'title' => 'Tarde', 'description' => nil },
                                        { 'id' => 'noite', 'title' => 'Noite', 'description' => nil }])
    end

    it 'opções sem nenhuma opção com título: sem pergunta viram nenhuma interação; com ela, a pergunta fica' do
      vazias = [[], [{}], [{ 'id' => 'a', 'titulo' => '', 'descricao' => nil }, { 'id' => 'b', 'titulo' => ' ', 'descricao' => nil }], ['x']]
      sem_pergunta = vazias.map { |lista| described_class.do_modelo(pedido.merge('opcoes' => lista, 'pergunta' => ' '), enderecos: Set.new) }
      expect(sem_pergunta).to all(be_nil)
      com_pergunta = vazias.map { |lista| described_class.do_modelo(pedido.merge('opcoes' => lista), enderecos: Set.new) }
      expect(com_pergunta).to all(include('tipo' => 'opcoes', 'pergunta' => 'Qual período?', 'opcoes' => []))
      com_uma = described_class.do_modelo(pedido.merge('opcoes' => [{ 'id' => 'a', 'titulo' => '' }, tres.first]), enderecos: Set.new)
      expect(com_uma['opcoes']).to eq([{ 'id' => 'manha', 'title' => 'Manhã', 'description' => nil }])
    end

    it 'usa o botão da lista escolhido pelo modelo' do
      expect(described_class.do_modelo(pedido.merge('botao' => 'Ver horários'), enderecos: Set.new)['botao']).to eq('Ver horários')
    end

    it 'aceita o link IGUAL a um endereço que o dono escreveu' do
      expect(link).to eq('tipo' => 'link', 'rotulo' => 'Abrir proposta', 'url' => url)
    end

    it 'descarta o link sem endereço' do
      expect(described_class.do_modelo({ 'tipo' => 'link', 'link' => { 'rotulo' => 'Abrir', 'url' => '' } }, enderecos: Set.new)).to be_nil
      expect(described_class.do_modelo({ 'tipo' => 'link', 'link' => nil }, enderecos: Set.new)).to be_nil
    end

    # As sondas da revisão do link: endereço inteiro, só de fonte do dono, http(s) com host.
    describe 'sondas do link' do
      it 'L1: pedaço de um endereço do dono não vale' do
        expect(pede_link('https://loja.com/pedido/42', 'Pague em https://loja.com/pedido/42/pagar')).to be_nil
        expect(pede_link('https://loja.com/pedido', 'Pague em https://loja.com/pedido?id=42')).to be_nil
      end

      it 'L2: endereço a mais (outro host ou caminho além do que o dono escreveu) não vale' do
        expect(pede_link('https://loja.com.golpe.net/pagar', 'Site: https://loja.com')).to be_nil
        expect(pede_link('https://loja.com/admin', 'Site: https://loja.com')).to be_nil
        expect(pede_link('https://inventado.com/x', 'veja https://inventado.com/')).to be_nil
      end

      it 'L3: só o esquema e o host aceitam diferença de maiúsculas; o resto tem de ser igual' do
        expect(pede_link('https://loja.exemplo.com/Fatura/8841', 'Pague em HTTPS://Loja.Exemplo.COM/Fatura/8841')).to be_present
        expect(pede_link('https://loja.exemplo.com/fatura/8841', 'Pague em https://loja.exemplo.com/Fatura/8841')).to be_nil
      end

      it 'L4: só http ou https, com host' do
        expect(pede_link('javascript:alert(1)', 'veja javascript:alert(1)')).to be_nil
        expect(pede_link('ftp://loja.com/arquivo', 'baixe em ftp://loja.com/arquivo')).to be_nil
        expect(pede_link('https:///sem-host', 'veja https:///sem-host')).to be_nil
        expect(pede_link('loja.com/pagar', 'veja loja.com/pagar')).to be_nil
        expect(pede_link('httpx://loja.com/pagar', 'veja httpx://loja.com/pagar')).to be_nil
      end

      it 'L5: o endereço inteiro sai do texto sem a pontuação colada, e com acento' do
        texto = 'Pague em https://loja.com/f/8841. Ou (https://loja.com/f/9), ou [aqui](https://loja.com/f/7) ou ' \
                'https://loja.com/serviços/limpeza!'
        expect(%w[https://loja.com/f/8841 https://loja.com/f/9 https://loja.com/f/7 https://loja.com/serviços/limpeza]
                 .map { |pedido| pede_link(pedido, texto).present? }).to all(be(true))
        expect(pede_link('https://loja.com/servi', texto)).to be_nil
      end

      it 'H5: endereço com usuário (user@) não vale, nem na fonte nem no pedido' do
        expect(pede_link('https://cliente@loja.com/a', 'veja https://cliente@loja.com/a')).to be_nil
        expect(pede_link('https://cliente@loja.com/a', 'veja https://loja.com/a')).to be_nil
        expect(pede_link('https://loja.com/a', 'veja https://cliente:senha@loja.com/a')).to be_nil
        expect(pede_link('https://@loja.com/a', 'veja https://@loja.com/a')).to be_nil
      end
    end
  end

  describe 'Enderecos.do_dono: saída de ferramenta' do
    def da_ferramenta(dono, saida)
      described_class::Enderecos.do_dono(dono: [dono], ferramentas: [saida])
    end

    it 'endereço do dono só com host libera o host inteiro, no mesmo esquema e porta (padrão escrita ou não)' do
      expect(da_ferramenta('https://loja.com', 'https://loja.com/pedido/1')).to include('https://loja.com/pedido/1')
      expect(da_ferramenta('https://loja.com/', 'https://loja.com/pedido/1')).to include('https://loja.com/pedido/1')
      expect(da_ferramenta('https://loja.com', 'https://loja.com:443/pedido/1')).to include('https://loja.com:443/pedido/1')
      expect(da_ferramenta('https://loja.com:8443', 'https://loja.com:8443/pedido/1')).to include('https://loja.com:8443/pedido/1')
    end

    it 'endereço do dono com caminho: a saída precisa começar por ele, em segmento inteiro' do
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/pedidos/42')).to include('https://loja.com/pedidos/42')
      expect(da_ferramenta('https://loja.com/pedidos/', 'https://loja.com/pedidos/42')).to include('https://loja.com/pedidos/42')
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/pedidos?id=1')).to include('https://loja.com/pedidos?id=1')
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/pedidos-falsos/42')).to eq(Set['https://loja.com/pedidos'])
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/conta/42')).to eq(Set['https://loja.com/pedidos'])
      expect(da_ferramenta('https://loja.com/pedidos/42', 'https://loja.com/pedidos')).to eq(Set['https://loja.com/pedidos/42'])
    end

    it 'barra invertida ou barra codificada no caminho não vale (o navegador trata \ como /)' do
      dono = 'https://loja.com/pedidos'
      ['https://loja.com/pedidos/..\..\admin', 'https://loja.com/pedidos/%5c..%5cadmin', 'https://loja.com/pedidos/%5C..%5Cadmin',
       'https://loja.com/pedidos/%2f..%2fadmin', 'https://loja.com/pedidos/a%2Fb'].each do |saida|
        expect(da_ferramenta(dono, saida)).to eq(Set[dono])
      end
      expect(da_ferramenta('https://loja.com', 'https://loja.com/a\b')).to eq(Set['https://loja.com'])
    end

    it 'endereço que o normalize recusa (`%E0` no host) não vale nem quebra' do
      expect(da_ferramenta('https://loja.com', 'https://%E0.com/x')).to eq(Set['https://loja.com'])
      expect { described_class::Enderecos.dentro?('https://%E0.com/x', 'https://%E0.com') }.not_to raise_error
      expect(described_class::Enderecos.dentro?('https://%E0.com/x', 'https://%E0.com')).to be(false)
      expect(pede_link('https://%E0.com/x', 'veja https://%E0.com/x')).to be_nil
      invalido = "https://x.com/\xff".b.force_encoding('UTF-8')
      expect(described_class::Enderecos.normalizado(invalido)).to be_nil
      expect(da_ferramenta('https://loja.com', "ver #{invalido} e https://loja.com/p")).to include('https://loja.com/p')
    end

    it 'host com mais de 253 caracteres não vale, e o Punycode que recusa não quebra' do
      longo = "https://#{'á' * 500}.com/x"
      expect(described_class::Enderecos.normalizado(longo)).to be_nil
      expect(described_class::Enderecos.normalizado("https://#{'a' * 253}/x")).to eq("https://#{'a' * 253}/x")
      expect(described_class::Enderecos.normalizado("https://#{'a' * 254}/x")).to be_nil
      expect(described_class::Enderecos.completo(longo)).to be_nil
      expect(described_class::Enderecos.dentro?(longo, longo)).to be(false)
      expect(da_ferramenta('https://loja.com', "#{longo} https://loja.com/p")).to eq(Set['https://loja.com', 'https://loja.com/p'])
    end

    it 'texto em UTF-16LE ou ISO-8859-1 vira UTF-8; UTF-8 válido fica igual' do
      expect(da_ferramenta('https://loja.com', 'veja https://loja.com/p'.encode('UTF-16LE'))).to include('https://loja.com/p')
      expect(da_ferramenta('https://loja.com', 'café https://loja.com/ç'.encode('ISO-8859-1'))).to include('https://loja.com/ç')
      expect(da_ferramenta('https://loja.com', 'café https://loja.com/ç')).to include('https://loja.com/ç')
    end

    it 'caminho com `..` ou `.` (também codificado) conta depois de resolvido' do
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/pedidos/../conta')).to eq(Set['https://loja.com/pedidos'])
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/pedidos/%2e%2e/conta')).to eq(Set['https://loja.com/pedidos'])
      expect(da_ferramenta('https://loja.com/pedidos', 'https://loja.com/x/../pedidos/1')).to include('https://loja.com/x/../pedidos/1')
    end

    it 'H2: outra porta, outro host ou outro esquema com outra porta não valem' do
      expect(da_ferramenta('https://loja.com', 'https://loja.com:8443/pedido/1')).not_to include('https://loja.com:8443/pedido/1')
      expect(da_ferramenta('https://loja.com', 'https://golpe.com/pedido/1')).not_to include('https://golpe.com/pedido/1')
      expect(da_ferramenta('https://loja.com', 'http://loja.com/pedido/1')).not_to include('http://loja.com/pedido/1')
      expect(da_ferramenta('https://loja.com:8443', 'http://loja.com:8443/pedido/1')).not_to include('http://loja.com:8443/pedido/1')
    end

    it 'H5: a saída com usuário (user@) não vale' do
      expect(da_ferramenta('https://loja.com', 'https://x@loja.com/pedido/1').size).to eq(1)
    end
  end

  describe '.limpa' do
    it 'passa cabeçalho, pergunta, botão, títulos, descrições e rótulo pelo bloco; id e endereço não' do
      lista = opcoes.merge('opcoes' => [{ 'id' => 'a', 'title' => 'Manhã', 'description' => 'cedo' }], 'botao' => 'Ver')
      limpa = described_class.limpa(lista, &:upcase)
      expect(limpa).to include('header' => 'AGENDAMENTO', 'pergunta' => 'QUAL PERÍODO?', 'botao' => 'VER',
                               'opcoes' => [{ 'id' => 'a', 'title' => 'MANHÃ', 'description' => 'CEDO' }])
      expect(described_class.limpa(link, &:upcase)).to eq(link.merge('rotulo' => 'ABRIR PROPOSTA'))
      expect(described_class.limpa(nil) { |texto| texto }).to be_nil
    end
  end

  describe '.mensagem' do
    it 'WhatsApp oficial com a janela aberta: botões, com cabeçalho e a pergunta no corpo' do
      janela_aberta
      final = described_class.mensagem(opcoes, texto: 'Temos vaga amanhã.', conversation: conversation)
      expect(final[:content]).to eq("Temos vaga amanhã.\n\nQual período?")
      expect(final[:rich_message]).to eq('type' => 'options', 'header' => 'Agendamento', 'button' => 'See options',
                                         'options' => [{ 'id' => 'manha', 'title' => 'Manhã' }, { 'id' => 'tarde', 'title' => 'Tarde' },
                                                       { 'id' => 'noite', 'title' => 'Noite' }])
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:native)
    end

    it 'o botão da lista sem texto do modelo sai no idioma da conta (en e pt_BR)' do
      janela_aberta
      botoes = %w[en pt_BR].map do |idioma|
        account.update!(locale: idioma)
        described_class.mensagem(opcoes, texto: nil, conversation: conversation.reload)[:rich_message]['button']
      end
      expect(botoes).to eq(['See options', 'Ver opções'])
    end

    it 'o botão escolhido pelo modelo vale em qualquer idioma' do
      janela_aberta
      account.update!(locale: 'pt_BR')
      final = described_class.mensagem(opcoes.merge('botao' => 'Ver horários'), texto: nil, conversation: conversation.reload)
      expect(final[:rich_message]['button']).to eq('Ver horários')
    end

    # Direto em `mensagem` (o `do_modelo` já tira o botão só de espaço; a limpeza da equipe pode deixá-lo assim depois).
    { 'mais de 20' => 'Escolha o melhor horário', 'quebra de linha' => "Ver\nhorários",
      'separador de linha' => "Ver\u2028horários", 'só espaço' => '   ' }.each do |caso, botao|
      it "botão do modelo fora do limite (#{caso}) cai no padrão e a lista continua saindo" do
        janela_aberta
        account.update!(locale: 'pt_BR')
        quatro = opcoes['opcoes'] + [{ 'id' => 'madrugada', 'title' => 'Madrugada', 'description' => nil }]
        final = described_class.mensagem(opcoes.merge('opcoes' => quatro, 'botao' => botao), texto: nil, conversation: conversation.reload)
        expect(final[:rich_message]).to include('type' => 'options', 'button' => 'Ver opções')
        expect(final[:content]).to eq('Qual período?')
        expect(RichMessages.build(Message.new(content_attributes: { 'rich_message' => final[:rich_message] }))
                 .whatsapp_cloud_payload('x')[:interactive][:type]).to eq('list')
      end
    end

    it 'botão do modelo com exatamente 20 caracteres fica como o modelo escreveu' do
      janela_aberta
      final = described_class.mensagem(opcoes.merge('botao' => 'a' * 20), texto: nil, conversation: conversation)
      expect(final[:rich_message]['button']).to eq('a' * 20)
    end

    it 'mais de 3 opções sai como lista, até 10' do
      janela_aberta
      dez = (1..10).map { |n| { 'id' => "o#{n}", 'titulo' => "Opção #{n}", 'descricao' => nil } }
      interacao = described_class.do_modelo(pedido.merge('opcoes' => dez), enderecos: Set.new)
      final = described_class.mensagem(interacao, texto: nil, conversation: conversation)
      expect(final[:content]).to eq('Qual período?')
      expect(RichMessages.build(Message.new(content_attributes: { 'rich_message' => final[:rich_message] }))
               .whatsapp_cloud_payload('x')[:interactive][:type]).to eq('list')
    end

    it 'mais de 10 opções sai em texto, com as opções numeradas' do
      janela_aberta
      onze = (1..11).map { |n| { 'id' => "o#{n}", 'titulo' => "Opção #{n}", 'descricao' => nil } }
      interacao = described_class.do_modelo(pedido.merge('opcoes' => onze), enderecos: Set.new)
      final = described_class.mensagem(interacao, texto: nil, conversation: conversation)
      expect(final[:rich_message]).to be_nil
      expect(final[:content]).to start_with("Qual período?\n\n1. Opção 1\n2. Opção 2")
      expect(final[:content]).to end_with('11. Opção 11')
    end

    it 'sem cabeçalho sai em texto: a pergunta e as opções numeradas' do
      janela_aberta
      final = described_class.mensagem(opcoes.merge('header' => nil), texto: 'Temos vaga.', conversation: conversation)
      expect(final).to eq(content: numerada, rich_message: nil, em_texto: numerada)
    end

    it 'opções vazias com pergunta: a resposta e a pergunta, em texto, mesmo na caixa que leva o formato' do
      janela_aberta
      vazias = described_class.do_modelo(pedido.merge('opcoes' => []), enderecos: Set.new)
      final = described_class.mensagem(vazias, texto: 'Temos vaga.', conversation: conversation)
      expect(final).to eq(content: "Temos vaga.\n\nQual período?", rich_message: nil, em_texto: "Temos vaga.\n\nQual período?")
      expect(described_class.mensagem(vazias, texto: nil, conversation: conversation)[:content]).to eq('Qual período?')
    end

    it 'em texto, a pergunta não se repete quando a resposta já termina com ela (depois de strip)' do
      janela_aberta
      vazias = described_class.do_modelo(pedido.merge('opcoes' => [], 'pergunta' => ' Qual período? '), enderecos: Set.new)
      expect(described_class.mensagem(vazias, texto: "Temos vaga. Qual período?\n", conversation: conversation)[:content])
        .to eq("Temos vaga. Qual período?\n")
      sem_cabecalho = described_class.mensagem(opcoes.merge('header' => nil), texto: 'Temos vaga. Qual período?', conversation: conversation)
      expect(sem_cabecalho[:content]).to eq("Temos vaga. Qual período?\n\n1. Manhã\n2. Tarde\n3. Noite")
      expect(described_class.mensagem(vazias, texto: 'Qual período? Temos vaga.', conversation: conversation)[:content])
        .to eq("Qual período? Temos vaga.\n\n Qual período? ")
    end

    it 'cabeçalho com mais de 60 caracteres sai em texto' do
      janela_aberta
      final = described_class.mensagem(opcoes.merge('header' => 'a' * 61), texto: nil, conversation: conversation)
      expect(final[:rich_message]).to be_nil
    end

    it 'WhatsApp oficial com a janela fechada leva o formato: o painel decide (texto na oficial, Híbrido pela rota dele)' do
      final = described_class.mensagem(opcoes, texto: nil, conversation: conversation)
      expect(RichMessages.delivery_mode(inbox: inbox, type: 'options', conversation: conversation)).to eq(:text)
      expect(final[:rich_message]).to include('type' => 'options')
    end

    it 'caixa API leva o formato (o painel manda a versão em texto)' do
      final = described_class.mensagem(opcoes, texto: nil, conversation: conversa_em(create(:channel_api, account: account)))
      expect(final[:rich_message]).to include('type' => 'options')
    end

    it 'e-mail e chat do site nunca recebem rich_message' do
      [create(:channel_email, account: account), create(:channel_widget, account: account)].each do |channel|
        final = described_class.mensagem(opcoes, texto: 'Temos vaga.', conversation: conversa_em(channel))
        expect(final).to eq(content: numerada, rich_message: nil, em_texto: numerada)
      end
    end

    it 'link: botão de link com o texto no corpo' do
      janela_aberta
      final = described_class.mensagem(link, texto: 'Sua proposta está pronta.', conversation: conversation)
      expect(final).to eq(content: 'Sua proposta está pronta.',
                          rich_message: { 'type' => 'link_button', 'label' => 'Abrir proposta', 'url' => url },
                          em_texto: "Sua proposta está pronta.\n\nAbrir proposta: #{url}")
    end

    it 'link fora do contrato (rótulo longo) sai em texto, com o endereço' do
      janela_aberta
      final = described_class.mensagem(link.merge('rotulo' => 'a' * 21), texto: 'Sua proposta.', conversation: conversation)
      expect(final).to eq(content: "Sua proposta.\n\n#{'a' * 21}: #{url}", rich_message: nil, em_texto: "Sua proposta.\n\n#{'a' * 21}: #{url}")
    end

    it 'link sozinho (depois do áudio): o rótulo é o corpo do botão; sem o formato, só "rótulo: endereço", sem repetir' do
      janela_aberta
      expect(described_class.mensagem(link, texto: nil, conversation: conversation))
        .to include(content: 'Abrir proposta', rich_message: hash_including('type' => 'link_button'))
      email = conversa_em(create(:channel_email, account: account))
      expect(described_class.mensagem(link, texto: nil, conversation: email))
        .to eq(content: "Abrir proposta: #{url}", rich_message: nil, em_texto: "Abrir proposta: #{url}")
    end

    it 'o link guarda o endereço conferido normalizado, no botão e na versão em texto' do
      janela_aberta
      normalizado = pede_link('HTTPS://Exemplo.com.br/x/../proposta', 'veja https://exemplo.com.br/x/../proposta')
      expect(normalizado['url']).to eq('https://exemplo.com.br/proposta')
      expect(described_class.mensagem(normalizado, texto: 'Pronto.', conversation: conversation)[:rich_message]['url'])
        .to eq('https://exemplo.com.br/proposta')
      email = conversa_em(create(:channel_email, account: account))
      expect(described_class.mensagem(normalizado, texto: 'Pronto.', conversation: email)[:content])
        .to eq("Pronto.\n\nAbrir proposta: https://exemplo.com.br/proposta")
    end

    it 'com o formato, a pergunta também não se repete no corpo quando a resposta já termina com ela' do
      janela_aberta
      final = described_class.mensagem(opcoes, texto: 'Temos vaga. Qual período?', conversation: conversation)
      expect(final[:content]).to eq('Temos vaga. Qual período?')
      expect(final[:rich_message]).to include('type' => 'options')
    end

    it 'não grava nem acrescenta mensagem à conversa ao conferir' do
      janela_aberta
      expect { described_class.mensagem(opcoes, texto: 'x', conversation: conversation) }.not_to change(Message, :count)
      expect(conversation.messages.reload.size).to eq(1)
    end
  end

  describe '.nos_pedacos' do
    let(:pedacos) { [{ 'text' => 'Temos vaga.', 'type' => 'text', 'delay_ms' => 900 }, { 'text' => 'Amanhã.', 'type' => 'text', 'delay_ms' => 800 }] }

    before { janela_aberta }

    it 'opções: um pedaço a mais, com a pergunta (corpo) e o formato; os outros sem formato' do
      novos = described_class.nos_pedacos(pedacos, opcoes, conversation: conversation)
      expect(novos.size).to eq(3)
      expect(novos.first(2)).to eq(pedacos)
      expect(novos.last).to include('corpo' => 'Qual período?', 'rich_message' => hash_including('type' => 'options'))
      expect(novos.last['delay_ms']).to be_a(Integer)
    end

    it 'link: o formato vai no último pedaço da resposta' do
      novos = described_class.nos_pedacos(pedacos, link, conversation: conversation)
      expect(novos.size).to eq(2)
      expect(novos.first).to eq(pedacos.first)
      expect(novos.last).to include('corpo' => 'Amanhã.', 'rich_message' => hash_including('type' => 'link_button'))
    end

    # Deploy com as stacks misturadas: o worker antigo não conhece `rich_message` nem `corpo` e manda o `text`.
    it 'o text do último pedaço é a versão em texto inteira, para o worker antigo' do
      expect(described_class.nos_pedacos(pedacos, opcoes, conversation: conversation).last['text'])
        .to eq("Qual período?\n\n1. Manhã\n2. Tarde\n3. Noite")
      expect(described_class.nos_pedacos(pedacos, link, conversation: conversation).last['text']).to eq("Amanhã.\n\nAbrir proposta: #{url}")
    end

    it 'sem o formato (caixa que o recusa), o pedaço é só texto, sem corpo' do
      ultimo = described_class.nos_pedacos(pedacos, opcoes.merge('header' => nil), conversation: conversation).last
      expect(ultimo).to include('text' => "Qual período?\n\n1. Manhã\n2. Tarde\n3. Noite")
      expect(ultimo.keys).not_to include('corpo', 'rich_message')
    end

    it 'opções vazias com pergunta: o pedaço a mais é a pergunta em texto; se o último pedaço já termina com ela, nada muda' do
      vazias = described_class.do_modelo(pedido.merge('opcoes' => []), enderecos: Set.new)
      novos = described_class.nos_pedacos(pedacos, vazias, conversation: conversation)
      expect(novos.size).to eq(3)
      expect(novos.last).to include('text' => 'Qual período?')
      expect(novos.last).not_to have_key('rich_message')
      repetida = [pedacos.first, pedacos.last.merge('text' => 'Amanhã. Qual período?')]
      expect(described_class.nos_pedacos(repetida, vazias, conversation: conversation)).to eq(repetida)
    end

    it 'opções cuja pergunta o último pedaço já traz: o formato vai nele, sem pedaço a mais' do
      repetida = [pedacos.first, pedacos.last.merge('text' => 'Amanhã. Qual período?')]
      novos = described_class.nos_pedacos(repetida, opcoes, conversation: conversation)
      expect(novos.size).to eq(2)
      expect(novos.last).to include('corpo' => 'Amanhã. Qual período?', 'rich_message' => hash_including('type' => 'options'))
    end

    it 'sem interação ou sem pedaço, nada muda' do
      expect(described_class.nos_pedacos(pedacos, nil, conversation: conversation)).to eq(pedacos)
      expect(described_class.nos_pedacos([], opcoes, conversation: conversation)).to eq([])
    end
  end
end

require 'rails_helper'

# As quatro ferramentas do Guia (#568, #590, #617), contra a aplicação de verdade.
#
# Nada aqui dubla a pilha: a leitura passa por rota, autenticação, controller e
# Pundit, a ação passa por `Acoes`, e a Central de Ajuda passa pelos mesmos
# filtros de papel e recurso que a tela usa. É o que sustenta o critério do
# Rodrigo — o que a pessoa vê na tela, a IA vê; o que ela não pode fazer, a IA
# não faz. São classes irmãs, e o que importa é o conjunto: com a mesma pessoa
# e o mesmo contexto. Separar em arquivos duplicaria o cenário inteiro para
# testar uma fração dele.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Ferramentas do Guia' do
  let(:conta_e_admin) { create_account_and_user }
  let(:conta) { conta_e_admin.first }
  let(:admin) { conta_e_admin.last }
  let(:agente) do
    Autonomia::Agents::Agent.create!(
      account: conta, name: 'Guia', agent_type: 'custom', status: :active, enabled: false,
      instruction: 'Guia.', config: { 'with_knowledge' => false }
    )
  end
  let(:operador) { Autonomia::Guide::Contexto.new(account: conta, user: admin) }
  let(:portal_central) { create(:portal, slug: 'plataforma', account: conta) }

  def ler(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaLeitura.new(agent: agente, params: params, operador: quem).call
  end

  def propor(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaAcao.new(agent: agente, params: params, operador: quem).call
  end

  def ler_central(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaCentral.new(agent: agente, params: params, operador: quem).call
  end

  # `central` carrega o que a meta tem além do id — hoje só `publico` e
  # `requer` — para o helper não crescer um parâmetro por chave nova.
  def artigo_central(id:, titulo:, descricao: 'Como fazer.', conteudo: 'Passo 1. Passo 2.', central: {})
    create(:article, account: conta, portal: portal_central, slug: "plataforma-#{id.tr('.', '-')}",
                     title: titulo, description: descricao, content: conteudo, status: :published,
                     meta: { 'central' => { 'id' => id }.merge(central) })
  end

  describe 'ler_da_conta' do
    it 'lê o que existe na conta de quem está perguntando' do
      create_crm_inbox(account: conta, name: 'Comercial', members: [admin])

      expect(ler({ 'recurso' => 'inboxes' })).to include('Comercial')
    end

    it 'preenche o :id da rota a partir do JSON que o modelo escreveu' do
      contato = conta.contacts.create!(name: 'Fulano de Tal')

      resposta = ler({ 'recurso' => 'contacts/:id', 'parametros_json' => { id: contato.id }.to_json })

      expect(resposta).to include('Fulano de Tal')
    end

    # JSON quebrado é coisa de modelo, não de usuário: não pode derrubar o turno.
    # A `Consulta` recusa pedindo o id, e o modelo lê isso e pergunta à pessoa.
    it 'não quebra com JSON malformado vindo do modelo' do
      expect(ler({ 'recurso' => 'contacts/:id', 'parametros_json' => '{id: sem aspas' }))
        .to include('preciso saber qual id')
    end

    it 'recusa recurso fora do catálogo em vez de tentar adivinhar' do
      expect(ler({ 'recurso' => 'admin/users' })).to include('Não sei consultar isso')
    end

    # #593 — o portão aceita a resposta que se apoia na conta. Leitura recusada
    # ou que falhou não é apoio de nada.
    it 'marca que leu a conta só quando a leitura trouxe dados', :aggregate_failures do
      ler({ 'recurso' => 'admin/users' })
      expect(operador.leu_a_conta?).to be(false)

      ler({ 'recurso' => 'labels' })
      expect(operador.leu_a_conta?).to be(true)
    end

    # Testar e playground não têm ninguém logado. Sem saber de quem é a
    # permissão, a ferramenta não inventa uma: recusa com frase que o modelo lê.
    it 'recusa sem derrubar o turno quando não há operador' do
      resposta = ler({ 'recurso' => 'inboxes' }, quem: nil)

      expect(resposta).to include('não sei quem está perguntando')
    end

    # O que destrava a lista longa: pedindo poucos campos, cabem muito mais
    # itens na mesma resposta. É a alternativa a eu adivinhar o que cortar.
    it 'devolve só os campos pedidos, e por isso cabe muito mais item', :aggregate_failures do
      12.times { |i| create_crm_inbox(account: conta, name: "Caixa #{i}", members: [admin]) }

      cheia = ler({ 'recurso' => 'inboxes' })
      enxuta = ler({ 'recurso' => 'inboxes', 'campos' => %w[id name] })

      expect(enxuta).to include('Caixa 0', 'Caixa 11')
      expect(enxuta.length).to be < cheia.length
      # Pediu id e name: o resto não vem, nem o que "identificaria".
      expect(enxuta).not_to include('channel_type')
    end

    # Sem o catálogo de campos o modelo não teria como saber o que pedir na
    # rodada seguinte — e a esteira voltaria pela porta dos fundos, comigo
    # adivinhando os campos certos para 270 recursos.
    it 'diz quais campos o recurso tem, para a próxima leitura ser dirigida' do
      create_crm_inbox(account: conta, name: 'Comercial', members: [admin])

      expect(ler({ 'recurso' => 'inboxes' })).to include('campos disponíveis neste recurso')
    end

    # O teto existe porque a saída de ferramenta é cortada em 8.000 pelo `Bound`,
    # e corte cego parte JSON no meio.
    it 'cabe no teto de saída de uma ferramenta' do
      40.times { |i| create_crm_inbox(account: conta, name: "Caixa #{i}", members: [admin]) }

      expect(ler({ 'recurso' => 'inboxes' }).length)
        .to be <= Autonomia::Agents::Tools::Native::GuiaLeitura::TETO
    end
  end

  describe 'propor_acao' do
    let(:pedido) do
      { 'acao' => 'POST labels', 'descricao' => 'Criar a etiqueta Urgente.',
        'corpo_json' => { title: 'urgente' }.to_json }
    end

    # O item mais importante do arquivo. A ferramenta PREPARA; quem grava é o
    # endpoint de confirmação, noutro request, depois do clique.
    it 'não toca no banco: prepara e espera a confirmação', :aggregate_failures do
      expect { propor(pedido) }.not_to change(conta.labels, :count)
      expect(propor(pedido)).to include('confirmar')
    end

    it 'deixa a proposta pronta para a tela mostrar o Confirmar', :aggregate_failures do
      propor(pedido)

      expect(operador.proposta[:nome]).to eq('POST labels')
      expect(operador.proposta[:descricao][:frase]).to eq('Criar a etiqueta Urgente.')
      expect(operador.proposta[:descricao][:detalhe]).to include('urgente')
    end

    # Sem frase não há confirmação informada, e cair no verbo com a rota traria
    # "POST labels" de volta para a tela de quem usa o produto.
    it 'recusa quando não veio a frase que a pessoa vai ler', :aggregate_failures do
      resposta = propor(pedido.merge('descricao' => ''))

      expect(operador.proposta).to be_nil
      expect(resposta).to be_present
    end

    # Quem não administra não escreve. A `Acoes` já barra; aqui o que se garante
    # é que a ferramenta repassa a recusa em vez de propor assim mesmo.
    it 'não prepara mudança para quem não administra a conta', :aggregate_failures do
      agente_comum, = create_crm_agent(account: conta)
      comum = Autonomia::Guide::Contexto.new(account: conta, user: agente_comum)

      propor(pedido, quem: comum)

      expect(comum.proposta).to be_nil
      expect(conta.labels.count).to eq(0)
    end

    # O catálogo de escrita tem 16.245 caracteres e não cabe no prompt de toda
    # pergunta. Ele chega aqui, no momento em que faz falta.
    it 'diz quais ações existem para o recurso quando o modelo erra o nome' do
      resposta = propor(pedido.merge('acao' => 'PUT labels/:id/arquivar'))

      expect(resposta).to include('POST labels')
    end

    it 'recusa sem derrubar o turno quando não há operador' do
      expect(propor(pedido, quem: nil)).to include('não sei quem está pedindo')
    end

    # #593 — "apaga a caixa do instagram": o nome se resolve LENDO a conta, e o
    # id da proposta tem que ser o que a leitura trouxe.
    describe 'apagar pelo nome' do
      let!(:caixa) { create_crm_inbox(account: conta, name: 'Instagram Loja', members: [admin]) }
      let(:apagar) do
        { 'acao' => 'DELETE inboxes/:id', 'descricao' => 'Apagar a caixa Instagram Loja.',
          'caminho_json' => { id: caixa.id }.to_json }
      end

      it 'propõe com o id que a leitura trouxe, sem apagar nada', :aggregate_failures do
        ler({ 'recurso' => 'inboxes', 'campos' => %w[id name] })

        propor(apagar)

        expect(operador.proposta[:nome]).to eq('DELETE inboxes/:id')
        expect(operador.proposta[:dados][:caminho]).to eq(id: caixa.id)
        expect(conta.inboxes.exists?(caixa.id)).to be(true)
      end

      it 'não propõe com id que nenhuma leitura trouxe', :aggregate_failures do
        resposta = propor(apagar)

        expect(operador.proposta).to be_nil
        expect(resposta).to include('não veio de nenhuma leitura')
      end
    end
  end

  describe 'mostrar_tela' do
    def mostrar(params, quem: operador)
      Autonomia::Agents::Tools::Native::GuiaTela.new(agent: agente, params: params, operador: quem).call
    end

    let(:caixa) { create_crm_inbox(account: conta, name: 'Sinistros', members: [admin]) }

    def caixa_da_leitura(quem: operador)
      caixa
      ler({ 'recurso' => 'inboxes', 'campos' => %w[id name] }, quem: quem)
      mostrar({ 'tela' => 'settings_inbox_show',
                'parametros_json' => { inboxId: caixa.id, tab: 'business-hours' }.to_json }, quem: quem)
    end

    it 'deixa o botão pronto com a tela de uma caixa e o id que leu', :aggregate_failures do
      caixa_da_leitura

      expect(operador.tela[:route_name]).to eq('settings_inbox_show')
      expect(operador.tela[:params]).to eq('inboxId' => caixa.id.to_s, 'tab' => 'business-hours')
    end

    # "abre a conversa 999": o número veio da pessoa, não da conta.
    it 'não monta botão para id que nenhuma leitura trouxe', :aggregate_failures do
      resposta = mostrar({ 'tela' => 'inbox_conversation', 'parametros_json' => { conversation_id: 999 }.to_json })

      expect(operador.tela).to be_nil
      expect(resposta).to include('não veio de nenhuma leitura')
    end

    # A regra do painel: a tela abre se a pessoa tem um dos papéis dela.
    it 'não monta botão de tela que o perfil de quem pergunta não abre', :aggregate_failures do
      agente_comum, = create_crm_agent(account: conta)
      caixa.add_members([agente_comum.id])
      comum = Autonomia::Guide::Contexto.new(account: conta, user: agente_comum)

      resposta = caixa_da_leitura(quem: comum)

      expect(comum.tela).to be_nil
      expect(resposta).to include('não abre para o perfil')
    end

    # A recusa volta PARA O MODELO, que lê a conta ou pergunta qual caixa.
    it 'diz ao modelo o que falta em vez de montar botão morto', :aggregate_failures do
      resposta = mostrar({ 'tela' => 'settings_inbox_show' })

      expect(operador.tela).to be_nil
      expect(resposta).to include('inboxId')
    end

    it 'não quebra com JSON malformado vindo do modelo' do
      expect(mostrar({ 'tela' => 'settings_inbox_show', 'parametros_json' => '{inboxId: 7' })).to include('inboxId')
    end

    it 'recusa sem derrubar o turno quando não há operador' do
      expect(mostrar({ 'tela' => 'labels_list' }, quem: nil)).to include('não sei quem está perguntando')
    end

    # #636 — pergunta com várias partes chama `mostrar_tela` mais de uma vez, e
    # cada chamada tem que ganhar o próprio botão.
    it 'empilha uma tela por chamada, na ordem em que o modelo chamou', :aggregate_failures do
      mostrar({ 'tela' => 'labels_list' })
      mostrar({ 'tela' => 'settings_inbox_new' })

      expect(operador.telas.map { |t| t[:route_name] }).to eq(%w[labels_list settings_inbox_new])
    end

    # Correção #636 (24/09/2026): o mapa é gerado sem acento e o título do fluxo descreve uma AÇÃO,
    # não a tela — "Criar contato" apareceu numa pergunta de IMPORTAR contatos. Agora o rótulo vem
    # de um parâmetro opcional que o PRÓPRIO MODELO manda, nunca do mapa.
    it 'usa o rótulo que o modelo mandou, limpo e cortado em 40 caracteres', :aggregate_failures do
      mostrar({ 'tela' => 'labels_list', 'rotulo' => '  Etiquetas do WhatsApp Business Oficial e tal  ' })

      expect(operador.tela[:rotulo]).to eq('Etiquetas do WhatsApp Business Oficial e')
      expect(operador.tela[:rotulo].length).to eq(40)
    end

    it 'sem rótulo do modelo, o botão fica sem nome' do
      mostrar({ 'tela' => 'labels_list' })

      expect(operador.tela[:rotulo]).to be_nil
    end
  end

  describe 'ler_da_central' do
    it 'devolve título, ref e o corpo do artigo, pela referência' do
      artigo_central(id: '02.04', titulo: 'Conectar o WhatsApp', conteudo: 'Vá em Canais e clique em Novo canal.')

      resposta = ler_central({ 'ref' => '02-04' })

      expect(resposta).to include('02-04', 'Conectar o WhatsApp', 'Vá em Canais e clique em Novo canal.')
    end

    # "02-04" (o formato do botão/rota) e "02.04" (o formato do id interno)
    # têm que achar o mesmo artigo.
    it 'aceita a referência nos dois formatos' do
      artigo_central(id: '02.04', titulo: 'Conectar o WhatsApp')

      expect(ler_central({ 'ref' => '02-04' })).to include('Conectar o WhatsApp')
      expect(ler_central({ 'ref' => '02.04' })).to include('Conectar o WhatsApp')
    end

    it 'na busca por termo, devolve a lista de resultados e o corpo do primeiro', :aggregate_failures do
      artigo_central(id: '02.04', titulo: 'Conectar o WhatsApp', descricao: 'Como ligar um canal de WhatsApp.',
                     conteudo: 'Vá em Canais e clique em Novo canal.')

      resposta = ler_central({ 'termo' => 'conectar whatsapp' })

      expect(resposta).to include('02-04', 'Conectar o WhatsApp', 'Vá em Canais e clique em Novo canal.')
    end

    # Achado na bateria real de 24/09/2026: a busca por termo registrava o
    # PRIMEIRO resultado como artigo lido, e o primeiro resultado nem sempre é
    # o artigo certo (ex.: "criar etiqueta" trouxe "Criar e editar uma Macro").
    # A busca por termo é só para o modelo LER a lista; quem escolhe o artigo
    # certo é o modelo, chamando de novo com `ref` — só essa chamada registra.
    it 'não registra o primeiro resultado da busca por termo como artigo lido', :aggregate_failures do
      artigo_central(id: '03.02', titulo: 'Criar uma etiqueta', descricao: 'Como criar etiqueta.')

      ler_central({ 'termo' => 'criar etiqueta' })
      expect(operador.artigos).to eq([])

      ler_central({ 'ref' => '03.02' })
      expect(operador.artigos).to eq([{ ref: '03-02', titulo: 'Criar uma etiqueta' }])
    end

    # O modelo precisa saber, sem ambiguidade, que a busca não achou nada —
    # senão ele responde como se tivesse achado (a mesma lição do #568).
    it 'diz claramente quando o termo não acha nada' do
      expect(ler_central({ 'termo' => 'xurupita completamente inexistente' })).to include('Não encontrei')
    end

    it 'diz claramente quando a referência não existe' do
      expect(ler_central({ 'ref' => '99.99' })).to include('Não encontrei')
    end

    # A mesma regra da tela: artigo de configuração não aparece para quem só atende.
    it 'não traz artigo de administrador para quem só atende' do
      artigo_central(id: '02.05', titulo: 'Configurar faturamento', central: { 'publico' => 'admin' })
      agente_comum, = create_crm_agent(account: conta)
      comum = Autonomia::Guide::Contexto.new(account: conta, user: agente_comum)

      expect(ler_central({ 'ref' => '02-05' }, quem: comum)).to include('Não encontrei')
    end

    it 'não traz artigo cujo recurso está desligado na conta' do
      artigo_central(id: '02.06', titulo: 'Macros da conta', central: { 'requer' => 'macros' })

      expect(ler_central({ 'ref' => '02-06' })).to include('Não encontrei')
    end

    it 'recusa sem derrubar o turno quando não há operador' do
      expect(ler_central({ 'ref' => '02.04' }, quem: nil)).to include('não sei qual é a conta')
    end

    # O botão "ler o artigo completo" (#617) lê daqui. Até a #636, só UM artigo
    # sobrevivia por turno, e o último vencia. Agora `ler_da_central` empilha
    # os artigos numa lista, na ordem de leitura — uma pergunta com várias
    # partes ("como conecto o WhatsApp e como conecto o Instagram") ganha um
    # link por artigo, não só o último.
    it 'guarda os artigos lidos no contexto, na ordem de leitura', :aggregate_failures do
      artigo_central(id: '02.04', titulo: 'Conectar o WhatsApp')
      artigo_central(id: '02.05', titulo: 'Conectar o Instagram')

      ler_central({ 'ref' => '02.04' })
      expect(operador.artigo).to eq(ref: '02-04', titulo: 'Conectar o WhatsApp')

      ler_central({ 'ref' => '02.05' })
      expect(operador.artigos).to eq([{ ref: '02-04', titulo: 'Conectar o WhatsApp' },
                                      { ref: '02-05', titulo: 'Conectar o Instagram' }])
      # O campo singular, mantido para o front antigo durante o deploy (#636),
      # é o PRIMEIRO da lista — não o último como antes.
      expect(operador.artigo).to eq(ref: '02-04', titulo: 'Conectar o WhatsApp')
    end
  end

  # O esquema é montado por `Native::Base` em strict mode. Um esquema inválido
  # não falha aqui: a OpenAI responde 400 na chamada INTEIRA e o Guia fica mudo,
  # em produção, sem erro em log nenhum. Já aconteceu uma vez.
  describe 'o esquema que vai para a OpenAI' do
    [Autonomia::Agents::Tools::Native::GuiaLeitura,
     Autonomia::Agents::Tools::Native::GuiaAcao,
     Autonomia::Agents::Tools::Native::GuiaTela,
     Autonomia::Agents::Tools::Native::GuiaCentral].each do |ferramenta|
      it "de #{ferramenta.slug} é válido em strict mode", :aggregate_failures do
        esquema = ferramenta.openai_schema(nil)
        parametros = esquema[:parameters]

        expect(esquema[:strict]).to be(true)
        expect(parametros[:additionalProperties]).to be(false)
        # Strict exige TODA propriedade em `required`; o opcional se diz pelo tipo.
        expect(parametros[:required]).to match_array(parametros[:properties].keys)
        # Objeto de chaves livres é o que derrubou o Guia em 21/09/2026.
        expect(parametros[:properties].values.map { |p| p['type'] || p[:type] }.flatten)
          .not_to include('object')
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass

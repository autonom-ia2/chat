require 'rails_helper'

# As duas ferramentas do Guia (#568), contra a aplicação de verdade.
#
# Nada aqui dubla a pilha: a leitura passa por rota, autenticação, controller e
# Pundit, e a ação passa por `Acoes`. É o que sustenta o critério do Rodrigo —
# o que a pessoa vê na tela, a IA vê; o que ela não pode fazer, a IA não faz.
# São duas classes irmãs, e o que importa é o par: ler e propor, com a mesma
# pessoa e o mesmo contexto. Separar em dois arquivos duplicaria o cenário
# inteiro para testar metade dele.
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

  def ler(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaLeitura.new(agent: agente, params: params, operador: quem).call
  end

  def propor(params, quem: operador)
    Autonomia::Agents::Tools::Native::GuiaAcao.new(agent: agente, params: params, operador: quem).call
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
  end

  # O esquema é montado por `Native::Base` em strict mode. Um esquema inválido
  # não falha aqui: a OpenAI responde 400 na chamada INTEIRA e o Guia fica mudo,
  # em produção, sem erro em log nenhum. Já aconteceu uma vez.
  describe 'o esquema que vai para a OpenAI' do
    [Autonomia::Agents::Tools::Native::GuiaLeitura,
     Autonomia::Agents::Tools::Native::GuiaAcao,
     Autonomia::Agents::Tools::Native::GuiaTela].each do |ferramenta|
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

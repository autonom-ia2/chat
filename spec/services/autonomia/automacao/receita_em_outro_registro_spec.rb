require 'rails_helper'

# G18 (#2671): o salvar do passo "em outro registro". O ramo roda no registro ligado e é conferido contra ele, não
# contra o alvo do gatilho; a âncora, contra o alvo do gatilho; e o passo não cabe no ramo de outro.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:cards_perdidos) { { 'de' => 'cards_do_contato', 'situacao' => ['lost'], 'mais_recente' => true } }
  let(:frase) { 'autonomia.automacao.receita' }
  # Decisão 16: o contato ligado fica num campo do card do tipo contato (Crm::CardCampoContato).
  let(:no_campo) { ->(caminho, usar = 'conversa') { { 'de' => 'contato_do_campo', 'campo' => { '$valor' => caminho }, 'usar' => usar } } }

  def receita(gatilho, *passos) = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => passos }

  # O gatilho de contato (G7), que não alcança card.
  def de_contato(*passos)
    gatilho = { 'tipo' => 'contato.recorrente', 'frequencia' => 'diaria', 'hora' => 8, 'selecao' => { 'etiqueta' => 'newsletter' } }
    { 'gatilho' => gatilho, 'passos' => passos }
  end

  def em_outro(registro, *passos) = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'registro' => registro, 'passos' => passos }

  def mensagem(id, caminho) = { 'id' => id, 'tipo' => 'mensagem', 'texto' => ['Oi ', { '$valor' => caminho }] }

  def problemas(receita, account_user: nil) = described_class.new(receita, conta: account, account_user: account_user).problemas

  def atributo(chave, modelo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: tipo)
  end

  # O gatilho de card (card.ganho, onde o campo do card existe) pede o CRM ligado.
  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  before do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens', 'automacao_gatilhos')
    atributo('indicado_por', 'card_attribute', 'contato')
  end

  it 'está no esquema e anda pela travessia única (a chave de funis do controller vê o ramo)', :aggregate_failures do
    lida = receita('mensagem.criada', em_outro(cards_perdidos, mensagem('m1', 'card.motivo_da_perda')))

    expect(described_class.esquema_valido?(lida)).to be(true)
    expect(described_class.new(lida, conta: account, account_user: nil).passos.pluck('id')).to eq(%w[outro m1])
  end

  it 'num gatilho de conversa, o ramo nos cards do contato lê o card: ele roda no card' do
    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos, mensagem('m1', 'card.motivo_da_perda'))))).to be_empty
  end

  it 'o ramo no contato não lê a conversa: ele roda no contato, que não tem conversa' do
    no_contato = no_campo.call('card.atributos.indicado_por', 'contato')

    expect(problemas(receita('card.ganho', em_outro(no_contato, mensagem('m1', 'conversa.status')))))
      .to eq([I18n.t("#{frase}.valor_fora_do_alvo", passo: 'm1', caminho: 'conversa.status')])
  end

  # Decisão 19 (#2716): a âncora lê o card da conversa, só para ler, e abre a filha a partir dele. A chave de funis de
  # quem salva fica no controller (spec de request) e a de quem ligou no Acesso (card_da_conversa_spec).
  it 'a âncora num gatilho de conversa lê o campo do card da conversa' do
    expect(problemas(receita('mensagem.criada', em_outro(no_campo.call('card.atributos.indicado_por'), mensagem('m1', 'contato.nome')))))
      .to be_empty
  end

  it 'a âncora é conferida no alvo do gatilho: card.* num gatilho de contato não tem de onde ler' do
    lida = de_contato(em_outro(no_campo.call('card.atributos.indicado_por'), mensagem('m1', 'contato.nome')))

    expect(problemas(lida)).to include(I18n.t("#{frase}.valor_fora_do_alvo", passo: 'outro', caminho: 'card.atributos.indicado_por'))
  end

  # Decisão 19: no ramo que roda numa conversa (o contato do campo, usar: conversa), o card dela é só para ler, como no
  # gatilho de conversa (Receita#alvo_da_receita); no ramo que roda nos cards do contato, a ação age no próprio card.
  describe 'o card da conversa no ramo, só para ler' do
    let(:na_conversa) { no_campo.call('card.atributos.indicado_por') }
    let(:so_le) { ->(id, caminho) { I18n.t("#{frase}.card_da_conversa_so_le", passo: id, caminho: caminho) } }

    def mover(id, caminho)
      { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover',
        'caminho' => { 'id' => { '$valor' => caminho } }, 'corpo' => { 'stage_id' => 1 } }
    end

    def gravar(id, caminho)
      { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
        'caminho' => { 'id' => { '$valor' => 'conversa.id' } }, 'corpo' => { 'custom_attributes' => { 'card' => { '$valor' => caminho } } } }
    end

    it 'lê o card no texto do ramo que roda numa conversa' do
      expect(problemas(receita('card.ganho', em_outro(na_conversa, mensagem('m1', 'card.titulo'))))).to be_empty
    end

    it 'recusa card.* no caminho e card.id no corpo de uma ação do ramo que roda numa conversa', :aggregate_failures do
      expect(problemas(receita('card.ganho', em_outro(na_conversa, mover('a1', 'card.id'))))).to include(so_le.call('a1', 'card.id'))
      expect(problemas(receita('card.ganho', em_outro(na_conversa, gravar('a2', 'card.id'))))).to include(so_le.call('a2', 'card.id'))
    end

    it 'no ramo que roda nos cards do contato, a ação age no próprio card' do
      expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos, mover('a1', 'card.id'))))).not_to include(so_le.call('a1', 'card.id'))
    end
  end

  # Decisão 16: a tela só oferece o campo do card do tipo contato; o servidor é a barreira de verdade (o Guia e a API
  # montam sem a tela). Campo de número não aponta contato: um engano mandaria a mensagem a outro cliente da conta.
  it 'o campo que guarda o contato tem de ser do tipo contato: o servidor recusa o de número e o resto', :aggregate_failures do
    atributo('numero_de_quem_indicou', 'card_attribute', 'number')
    atributo('quem_indicou', 'contact_attribute', 'number')
    atributo('telefone_de_quem_indicou', 'contact_attribute', 'text')
    recusado = [I18n.t('autonomia.automacao.receita.em_outro_registro.campo_sem_contato', passo: 'outro')]

    expect(problemas(receita('card.ganho', em_outro(no_campo.call('card.atributos.indicado_por'))))).to be_empty
    %w[card.atributos.numero_de_quem_indicou contato.atributos.quem_indicou contato.id contato.telefone
       contato.atributos.telefone_de_quem_indicou].each do |caminho|
      expect(problemas(receita('card.ganho', em_outro(no_campo.call(caminho))))).to eq(recusado)
    end
  end

  describe 'G65 (#2842): o ramo lê o registro de origem com origem.*' do
    # O ramo nos cards do contato de um gatilho de conversa: a origem é a conversa, que lê o card dela só para ler.
    let(:no_contato) { cards_perdidos }

    def texto(chave, id, caminho) = I18n.t("#{frase}.#{chave}", passo: id, caminho: caminho)

    it 'vale só dentro do ramo, com o caminho que o alvo do gatilho da mãe alcança', :aggregate_failures do
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'origem.contato.nome'))))).to be_empty
      expect(problemas(receita('mensagem.criada', mensagem('m0', 'origem.contato.nome'), em_outro(no_contato, mensagem('m1', 'contato.nome')))))
        .to eq([texto(:origem_fora_do_ramo, 'm0', 'origem.contato.nome')])
      expect(problemas(de_contato(em_outro(no_contato, mensagem('m1', 'origem.card.titulo')))))
        .to include(texto(:valor_fora_do_alvo, 'm1', 'origem.card.titulo'))
    end

    # Decisão 19: a origem conversa lê o card dela (o assunto atual), só para ler; agir nele pela origem é recusado.
    it 'na origem conversa, origem.card.* é lido e nunca aponta a ação', :aggregate_failures do
      mover = { 'id' => 'a1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover',
                'caminho' => { 'id' => { '$valor' => 'origem.card.id' } }, 'corpo' => { 'stage_id' => 1 } }
      gravar = { 'id' => 'a2', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
                 'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
                 'corpo' => { 'custom_attributes' => { 'card' => { '$valor' => 'origem.card.id' } } } }

      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'origem.card.titulo'))))).to be_empty
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mover))))
        .to include(texto(:card_da_conversa_so_le, 'a1', 'origem.card.id'))
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, gravar))))
        .to include(texto(:card_da_conversa_so_le, 'a2', 'origem.card.id'))
    end

    it 'só campos e atributos da conversa, do contato e do card: o resto é da execução da mãe', :aggregate_failures do
      %w[origem.mensagem.tipo origem.ia.p1 origem.envio.texto origem.conversa.cliente_respondeu origem.conversa.link_da_agenda
         origem.origem.contato.nome].each do |caminho|
        expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', caminho)))))
          .to eq([texto(:valor_desconhecido, 'm1', caminho)])
      end
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'origem.contato.atributos.sumiu')))))
        .to eq([texto(:atributo_inexistente, 'm1', 'origem.contato.atributos.sumiu')])
    end

    it 'o valor protegido do registro de origem segue a permissão de quem salva', :aggregate_failures do
      account.enable_features!('automacao_gatilhos')
      lida = receita('card.ganho', em_outro(no_campo.call('card.atributos.indicado_por'), mensagem('m1', 'origem.card.valor')))
      sem_valor = create(:account_user, account: account, role: :agent,
                                        custom_role: create(:custom_role, account: account, permissions: %w[automation_manage crm_view]))
      dona = create(:account_user, account: account, role: :administrator)

      expect(problemas(lida, account_user: sem_valor)).to include(texto(:valor_de_venda, 'm1', 'origem.card.valor'))
      expect(problemas(lida, account_user: dona)).not_to include(texto(:valor_de_venda, 'm1', 'origem.card.valor'))
    end
  end

  # #2716 dentro do ramo: o ramo que roda numa conversa lê o card dela, mas não age nele, mesmo com gatilho de contato.
  it 'o ramo na conversa do contato recusa o card no caminho e o id dele no corpo', :aggregate_failures do
    na_conversa = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'contato.id' }, 'usar' => 'conversa' }
    mover = { 'id' => 'a1', 'tipo' => 'acao', 'acao' => 'POST crm/cards/:id/move', 'descricao' => 'Mover',
              'caminho' => { 'id' => { '$valor' => 'card.id' } }, 'corpo' => { 'stage_id' => 1 } }
    nota = { 'id' => 'a2', 'tipo' => 'acao', 'acao' => 'POST conversations/:id/custom_attributes', 'descricao' => 'Gravar',
             'caminho' => { 'id' => { '$valor' => 'conversa.id' } },
             'corpo' => { 'custom_attributes' => { 'card' => { '$valor' => 'card.id' } } } }
    gatilho = { 'tipo' => 'contato.data', 'campo' => 'nascimento', 'quando' => 'antes', 'dias' => 1, 'hora' => 9 }
    so_le = ->(passo) { I18n.t("#{frase}.card_da_conversa_so_le", passo: passo, caminho: 'card.id') }

    expect(problemas({ 'gatilho' => gatilho, 'passos' => [em_outro(na_conversa, mover)] })).to include(so_le.call('a1'))
    expect(problemas({ 'gatilho' => gatilho, 'passos' => [em_outro(na_conversa, nota)] })).to include(so_le.call('a2'))
    expect(problemas({ 'gatilho' => gatilho, 'passos' => [em_outro(na_conversa, mensagem('m1', 'card.titulo'))] }))
      .not_to include(a_string_including('card.titulo'))
  end

  it 'recusa "em outro registro" dentro de outro: a filha nunca abre netas' do
    neto = em_outro(cards_perdidos).merge('id' => 'neto')

    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos, neto))))
      .to eq([I18n.t("#{frase}.em_outro_registro.aninhado", passo: 'neto')])
  end

  it 'recusa o funil e a etapa de outra conta', :aggregate_failures do
    de_fora = create(:account)
    funil, etapa = create_crm_pipeline(account: de_fora, user: create(:user, account: de_fora), name: 'De fora')

    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos.merge('funil_id' => funil.id)))))
      .to eq([I18n.t("#{frase}.em_outro_registro.funil_de_fora", passo: 'outro')])
    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos.merge('etapa_id' => etapa.id)))))
      .to eq([I18n.t("#{frase}.em_outro_registro.etapa_de_fora", passo: 'outro')])
  end

  it 'nos cards do contato, quem salva sem a chave de funis é recusado' do
    agente = create(:account_user, account: account, role: :agent)

    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos)), account_user: agente))
      .to eq([I18n.t("#{frase}.em_outro_registro.sem_chave_de_funis", passo: 'outro')])
  end

  # As regras de "só no card" leem o alvo da receita (Receita#alvo): no ramo nos cards do contato, o card do ramo; fora do
  # ramo, o do gatilho. O ramo nasce com `gatilho` vazio, e ler o tipo do gatilho recusava o passo válido.
  describe 'o que só vale no card' do
    let(:aviso) { { 'id' => 'aviso', 'tipo' => 'avisar', 'para' => { 'responsavel_do_card' => true }, 'texto' => ['Oi'] } }
    let(:conversa) { { 'id' => 'conversa', 'tipo' => 'conversa_ao_responsavel' } }
    let(:retorno) do
      { 'id' => 'retorno', 'tipo' => 'retorno', 'titulo' => ['Ligar'], 'daqui' => { 'valor' => 2, 'unidade' => 'dias' },
        'envio' => { 'mensagem' => ['Oi'] } }
    end

    it 'vale no ramo nos cards do contato, num gatilho de conversa', :aggregate_failures do
      [aviso, conversa, retorno].each do |passo|
        lida = receita('mensagem.criada', em_outro(cards_perdidos, passo))

        expect(described_class.esquema_valido?(lida)).to be(true)
        expect(problemas(lida)).to eq([])
      end
    end

    it 'fora do ramo, num gatilho de conversa, continua recusado', :aggregate_failures do
      expect(problemas(receita('mensagem.criada', aviso)))
        .to eq([I18n.t("#{frase}.responsavel_do_card_sem_card", passo: 'aviso')])
      expect(problemas(receita('mensagem.criada', conversa))).to eq([I18n.t("#{frase}.responsavel_so_com_card", passo: 'conversa')])
      expect(problemas(receita('mensagem.criada', retorno))).to eq([I18n.t("#{frase}.retorno_mensagem_sem_card", passo: 'retorno')])
    end
  end

  it 'o id repetido entre o ramo e o resto sai uma vez só' do
    lida = receita('mensagem.criada', mensagem('m1', 'contato.nome'), em_outro(cards_perdidos, mensagem('m1', 'card.titulo')))

    expect(problemas(lida)).to eq([I18n.t("#{frase}.id_repetido", passo: 'm1')])
  end
end

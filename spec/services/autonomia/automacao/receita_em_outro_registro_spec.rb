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

  it 'a âncora é conferida no alvo do gatilho: card.* num gatilho de conversa não tem de onde ler' do
    expect(problemas(receita('mensagem.criada', em_outro(no_campo.call('card.atributos.indicado_por'), mensagem('m1', 'contato.nome')))))
      .to include(I18n.t("#{frase}.valor_fora_do_alvo", passo: 'outro', caminho: 'card.atributos.indicado_por'))
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
    # O ramo nos cards do contato de um gatilho de conversa: a origem é a conversa, que não alcança card.
    let(:no_contato) { cards_perdidos }

    def texto(chave, id, caminho) = I18n.t("#{frase}.#{chave}", passo: id, caminho: caminho)

    it 'vale só dentro do ramo, com o caminho que o alvo do gatilho da mãe alcança', :aggregate_failures do
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'origem.contato.nome'))))).to be_empty
      expect(problemas(receita('mensagem.criada', mensagem('m0', 'origem.contato.nome'), em_outro(no_contato, mensagem('m1', 'contato.nome')))))
        .to eq([texto(:origem_fora_do_ramo, 'm0', 'origem.contato.nome')])
      expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'origem.card.titulo')))))
        .to eq([texto(:valor_fora_do_alvo, 'm1', 'origem.card.titulo')])
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

  it 'o id repetido entre o ramo e o resto sai uma vez só' do
    lida = receita('mensagem.criada', mensagem('m1', 'contato.nome'), em_outro(cards_perdidos, mensagem('m1', 'card.titulo')))

    expect(problemas(lida)).to eq([I18n.t("#{frase}.id_repetido", passo: 'm1')])
  end
end

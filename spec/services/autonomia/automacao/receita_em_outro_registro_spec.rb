require 'rails_helper'

# G18 (#2671): o salvar do passo "em outro registro". O ramo roda no registro ligado e é conferido contra ele, não
# contra o alvo do gatilho; a âncora, contra o alvo do gatilho; e o passo não cabe no ramo de outro.
RSpec.describe Autonomia::Automacao::Receita do
  let(:account) { create(:account) }
  let(:cards_perdidos) { { 'de' => 'cards_do_contato', 'situacao' => ['lost'], 'mais_recente' => true } }
  let(:frase) { 'autonomia.automacao.receita' }

  def receita(gatilho, *passos) = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => passos }

  def em_outro(registro, *passos) = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'registro' => registro, 'passos' => passos }

  def mensagem(id, caminho) = { 'id' => id, 'tipo' => 'mensagem', 'texto' => ['Oi ', { '$valor' => caminho }] }

  def problemas(receita, account_user: nil) = described_class.new(receita, conta: account, account_user: account_user).problemas

  before { account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens') }

  it 'está no esquema e anda pela travessia única (a chave de funis do controller vê o ramo)', :aggregate_failures do
    lida = receita('mensagem.criada', em_outro(cards_perdidos, mensagem('m1', 'card.motivo_da_perda')))

    expect(described_class.esquema_valido?(lida)).to be(true)
    expect(described_class.new(lida, conta: account, account_user: nil).passos.pluck('id')).to eq(%w[outro m1])
  end

  it 'num gatilho de conversa, o ramo nos cards do contato lê o card: ele roda no card' do
    expect(problemas(receita('mensagem.criada', em_outro(cards_perdidos, mensagem('m1', 'card.motivo_da_perda'))))).to be_empty
  end

  it 'o ramo no contato não lê a conversa: ele roda no contato, que não tem conversa' do
    no_contato = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'contato.id' }, 'usar' => 'contato' }

    expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'conversa.status')))))
      .to eq([I18n.t("#{frase}.valor_fora_do_alvo", passo: 'm1', caminho: 'conversa.status')])
  end

  it 'a âncora é conferida no alvo do gatilho: card.* num gatilho de conversa não tem de onde ler' do
    do_card = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'card.atributos.indicado_por' }, 'usar' => 'conversa' }

    expect(problemas(receita('mensagem.criada', em_outro(do_card, mensagem('m1', 'contato.nome')))))
      .to include(I18n.t("#{frase}.valor_fora_do_alvo", passo: 'outro', caminho: 'card.atributos.indicado_por'))
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

  it 'o id repetido entre o ramo e o resto sai uma vez só' do
    lida = receita('mensagem.criada', mensagem('m1', 'contato.nome'), em_outro(cards_perdidos, mensagem('m1', 'card.titulo')))

    expect(problemas(lida)).to eq([I18n.t("#{frase}.id_repetido", passo: 'm1')])
  end
end

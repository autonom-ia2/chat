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

  def atributo(chave, modelo, tipo)
    create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: chave,
                                         attribute_model: modelo, attribute_display_type: tipo)
  end

  before do
    account.enable_features!('automacao_fundacao', 'automacao_motor', 'automacao_mensagens')
    atributo('indicado_por', 'contact_attribute', 'number')
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
    no_contato = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'contato.atributos.indicado_por' }, 'usar' => 'contato' }

    expect(problemas(receita('mensagem.criada', em_outro(no_contato, mensagem('m1', 'conversa.status')))))
      .to eq([I18n.t("#{frase}.valor_fora_do_alvo", passo: 'm1', caminho: 'conversa.status')])
  end

  it 'a âncora é conferida no alvo do gatilho: card.* num gatilho de conversa não tem de onde ler' do
    do_card = { 'de' => 'contato_do_campo', 'campo' => { '$valor' => 'card.atributos.indicado_por' }, 'usar' => 'conversa' }

    expect(problemas(receita('mensagem.criada', em_outro(do_card, mensagem('m1', 'contato.nome')))))
      .to include(I18n.t("#{frase}.valor_fora_do_alvo", passo: 'outro', caminho: 'card.atributos.indicado_por'))
  end

  # A tela só oferece campo de número; o servidor é a barreira de verdade (o Guia e a API montam sem a tela).
  it 'o campo que guarda o contato tem de ser um campo de número: o servidor recusa o resto', :aggregate_failures do
    atributo('telefone_de_quem_indicou', 'contact_attribute', 'text')
    campo = ->(caminho) { { 'de' => 'contato_do_campo', 'campo' => { '$valor' => caminho }, 'usar' => 'conversa' } }
    recusado = [I18n.t("#{frase}.em_outro_registro.campo_sem_contato", passo: 'outro')]

    expect(problemas(receita('mensagem.criada', em_outro(campo.call('contato.atributos.indicado_por'))))).to be_empty
    %w[contato.id contato.telefone contato.atributos.telefone_de_quem_indicou].each do |caminho|
      expect(problemas(receita('mensagem.criada', em_outro(campo.call(caminho))))).to eq(recusado)
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

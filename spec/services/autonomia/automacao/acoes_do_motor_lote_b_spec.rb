require 'rails_helper'

# #2660 lote B: contato e card pela porta da automação. Criar contato (G17), criar o contato do card com a chave que a
# rota pede (D7) e restaurar card sem o `force`.
RSpec.describe Autonomia::Automacao::AcoesDoMotor, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:definicao) { create(:autonomia_automacao, account: account, ligada_por: admin) }
  let(:execucao) { create(:autonomia_automacao_execucao, versao: create(:autonomia_automacao_versao, automacao: definicao), alvo: conversa) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin) }
  let(:card) do
    account.crm_cards.create!(pipeline: funil_e_etapa.first, stage: funil_e_etapa.last, owner: admin, title: 'Pedido', currency: 'BRL')
  end

  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  after { Current.reset }

  def acoes(da_execucao = execucao)
    described_class.new(execucao: da_execucao, account_user: account.account_users.find_by(user: admin))
  end

  def contato_do_card(nome = 'Maria Indicada')
    { caminho: { card_id: card.id }, corpo: { contact: { name: nome } }, descricao: 'Criar o contato do card' }
  end

  it 'cria o contato, sem deixar mandar o source_id', :aggregate_failures do
    criar = { corpo: { name: 'Amigo indicado', email: 'amigo@example.com' }, descricao: 'Criar o contato' }
    execucao # a conversa da execução traz o contato dela: fica fora da contagem

    expect { acoes.executar('POST contacts', criar) }.to change(account.contacts, :count).by(1)
    expect(account.contacts.from_email('amigo@example.com').name).to eq('Amigo indicado')

    com_source = { corpo: { name: 'Outro', source_id: 'de-outro-contato' }, descricao: 'Criar o contato' }
    expect { acoes.executar('POST contacts', com_source) }
      .to raise_error(Autonomia::Guide::Acoes::Recusada, I18n.t('autonomia.automacao.motivos.campo_proibido'))
  end

  it 'cria o contato do card com a chave; o passo repetido na mesma execução não cria outro', :aggregate_failures do
    primeira = acoes.executar('POST crm/cards/:card_id/contact', contato_do_card)
    contato = card.reload.contact

    expect(primeira.ok).to be(true)
    expect(contato.name).to eq('Maria Indicada')
    expect { acoes.executar('POST crm/cards/:card_id/contact', contato_do_card) }.not_to change(Contact, :count)
    expect(card.reload.contact).to eq(contato)
  end

  it 'outra execução com o mesmo pedido leva outra chave' do
    outra = create(:autonomia_automacao_execucao, versao: execucao.versao, alvo: create(:conversation, account: account))
    acoes.executar('POST crm/cards/:card_id/contact', contato_do_card)
    desligar = acoes.executar('POST crm/cards/:id/unlink_contact', { caminho: { id: card.id }, descricao: 'Desligar o contato' })
    expect(desligar.ok).to be(true)

    expect { acoes(outra).executar('POST crm/cards/:card_id/contact', contato_do_card) }.to change(Contact, :count).by(1)
  end

  it 'só a rota que pede a chave a recebe' do
    chamadas = []
    allow(Autonomia::Guide::ChamadaInterna).to receive(:new).and_wrap_original do |nova, **argumentos|
      nova.call(**argumentos).tap do |chamada|
        allow(chamada).to receive(:chamar).and_wrap_original do |original, *args, **opcoes|
          chamadas << opcoes[:cabecalhos]
          original.call(*args, **opcoes)
        end
      end
    end

    acoes.executar('PATCH crm/cards/:id', { caminho: { id: card.id }, corpo: { title: 'Pedido novo' }, descricao: 'Renomear' })
    acoes.executar('POST crm/cards/:card_id/contact', contato_do_card)

    expect(chamadas.first).to eq({})
    expect(chamadas.last.keys).to eq(['Idempotency-Key'])
  end

  it 'restaurar o card não aceita o force' do
    restaurar = { caminho: { id: card.id }, corpo: { force: true }, descricao: 'Restaurar' }

    expect { acoes.executar('POST crm/cards/:id/restore', restaurar) }
      .to raise_error(Autonomia::Guide::Acoes::Recusada, I18n.t('autonomia.automacao.motivos.campo_proibido'))
  end
end

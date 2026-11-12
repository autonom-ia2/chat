require 'rails_helper'

# #2894 — as ações em grupo da Lista nova de Relacionamentos, pessoa por pessoa: a falha de uma não derruba as outras e
# aparece em "de fora"; erro de programa não se disfarça de "de fora". O contrato da API está em relacionamentos_acoes_spec.rb.
RSpec.describe Relacionamentos::AcaoEmGrupo do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:vendas) { create_crm_pipeline(account: account, user: admin, name: 'Vendas') }
  let!(:ana) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let!(:bruno) { create(:contact, account: account, name: 'Bruno Brandolim') }
  let!(:carla) { create(:contact, account: account, name: 'Carla Carvalhedo') }
  let(:todos) { [ana.id, bruno.id, carla.id] }

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  def de_fora(contato, motivo)
    { id: contato.id, nome: contato.name, motivo: motivo }
  end

  def o_rastreador_recebe(erro)
    rastreador = instance_double(ChatwootExceptionTracker, capture_exception: nil)
    allow(ChatwootExceptionTracker).to receive(:new).with(instance_of(erro), account: account, user: admin).and_return(rastreador)
    rastreador
  end

  describe Relacionamentos::CriarCards do
    def criar(pessoa_ids = todos, user: admin, funil: vendas)
      described_class.new(account: account, user: user, pessoa_ids: pessoa_ids, funil_id: funil.first.id, etapa_id: funil.last.id).call
    end

    def criador_que_falha_com(contato, erro)
      allow(Crm::Cards::Creator).to receive(:new).and_wrap_original do |original, **dados|
        raise erro if dados[:params][:contact_id] == contato.id

        original.call(**dados)
      end
    end

    it 'chama o card pelo nome da pessoa; sem nome, pelo telefone ou pelo e-mail' do
      bruno.update!(name: '', phone_number: '+5511910310002')
      carla.update!(name: '', email: 'carla.carvalhedo@exemplo.com.br')

      expect(criar).to eq(criados: 3, de_fora: [])
      expect(account.crm_cards.order(:id).pluck(:title)).to eq(['Ana Albuquerino', '+5511910310002', 'carla.carvalhedo@exemplo.com.br'])
    end

    it 'deixa de fora a pessoa que não tem como dar nome ao card; as outras ganham o delas' do
      bruno.update!(name: '')

      expect(criar).to eq(criados: 2, de_fora: [de_fora(bruno, 'dados_invalidos')])
      expect(account.crm_cards.pluck(:contact_id)).to contain_exactly(ana.id, carla.id)
    end

    it 'anota na linha do tempo que a etapa foi escolhida por uma pessoa, e avisa o quadro de cada card' do
      allow(Crm::Cards::Broadcaster).to receive(:broadcast)

      criar([ana.id, bruno.id])

      cards = account.crm_cards.order(:id).to_a
      expect(cards.map { |card| card.activities.sole.payload.slice('etapa_escolhida', 'contact_id') })
        .to eq([{ 'etapa_escolhida' => true, 'contact_id' => ana.id }, { 'etapa_escolhida' => true, 'contact_id' => bruno.id }])
      cards.each { |card| expect(Crm::Cards::Broadcaster).to have_received(:broadcast).with(card, Events::Types::CRM_CARD_CREATED) }
    end

    it 'falha do banco numa pessoa não derruba as outras: ela fica de fora e o erro vai ao rastreador' do
      criador_que_falha_com(bruno, ActiveRecord::Deadlocked.new('deadlock detected'))
      rastreador = o_rastreador_recebe(ActiveRecord::Deadlocked)

      expect(criar).to eq(criados: 2, de_fora: [de_fora(bruno, 'erro')])
      expect(account.crm_cards.pluck(:contact_id)).to contain_exactly(ana.id, carla.id)
      expect(rastreador).to have_received(:capture_exception).once
    end

    it 'não disfarça erro de programa de "ficou de fora": o pedido estoura' do
      criador_que_falha_com(bruno, NoMethodError.new('undefined method'))

      expect { criar }.to raise_error(NoMethodError)
    end

    # SQL que o banco recusa (coluna que não existe, sintaxe) é defeito nosso, não falha daquela pessoa.
    it 'não disfarça consulta errada de "ficou de fora": o pedido estoura' do
      criador_que_falha_com(bruno, ActiveRecord::StatementInvalid.new('PG::UndefinedColumn'))

      expect { criar }.to raise_error(ActiveRecord::StatementInvalid)
    end

    it 'deixa de fora quem foi apagada entre a conferência e a vez dela' do
      allow(Crm::Cards::Creator).to receive(:new).and_wrap_original do |original, **dados|
        Contact.where(id: carla.id).delete_all if dados[:params][:contact_id] == ana.id
        original.call(**dados)
      end

      expect(criar).to eq(criados: 2, de_fora: [de_fora(carla, 'nao_existe_mais')])
    end

    # Acesso por funil (#1148): o funil que a pessoa não enxerga é, para ela, um funil que não existe.
    it 'não cria card em funil que quem pede não enxerga' do
      sinistro = create_crm_pipeline(account: account, user: admin, name: 'Sinistro')
      caixa = create(:inbox, account: account)
      account.crm_pipeline_inboxes.create!(pipeline: vendas.first, inbox: caixa)
      account.crm_pipeline_inboxes.create!(pipeline: sinistro.first, inbox: create(:inbox, account: account))
      vendedora = create(:user, account: account, role: :agent)
      create(:inbox_member, user: vendedora, inbox: caixa)
      acesso = Crm::InboxAgentAccess.create!(account: account, inbox: caixa, user: vendedora, all_pipelines: false, triage: false)
      acesso.agent_pipelines.create!(account: account, pipeline: vendas.first)

      expect { criar([ana.id], user: vendedora, funil: sinistro) }.to raise_error(Relacionamentos::PedidoInvalido, 'funil desconhecido')
      expect(criar([ana.id], user: vendedora, funil: vendas)).to eq(criados: 1, de_fora: [])
      expect(account.crm_cards.pluck(:pipeline_id)).to eq([vendas.first.id])
    end
  end

  describe Relacionamentos::AplicarEtiqueta do
    before { create(:label, account: account, title: 'feira') }

    def etiquetar
      described_class.new(account: account, user: admin, pessoa_ids: todos, etiqueta: 'feira').call
    end

    it 'deixa de fora a pessoa com dado antigo que não passa mais na validação; as outras recebem a etiqueta' do
      bruno.update_column(:phone_number, '123') # rubocop:disable Rails/SkipsModelValidations

      expect(etiquetar).to eq(aplicadas: 2, de_fora: [de_fora(bruno, 'dados_invalidos')])
      expect([ana, bruno, carla].map { |contato| contato.reload.label_list }).to eq([%w[feira], [], %w[feira]])
    end

    it 'deixa de fora quem foi apagada entre a conferência e a vez dela' do
      allow(Contacts::BulkAssignLabelsService).to receive(:new).and_wrap_original do |original, **dados|
        Contact.where(id: carla.id).delete_all if dados[:contact_ids] == [ana.id]
        original.call(**dados)
      end

      expect(etiquetar).to eq(aplicadas: 2, de_fora: [de_fora(carla, 'nao_existe_mais')])
    end
  end

  describe Relacionamentos::Apagar do
    def apagar
      described_class.new(account: account, user: admin, pessoa_ids: todos).call
    end

    # Sem a chave crm_arquivados a exclusão em lote de hoje estoura na primeira que não sai e larga o resto.
    it 'a pessoa que o banco não deixa sair fica de fora, inteira; as outras saem' do
      allow(Contacts::BulkDeleteService).to receive(:new).and_wrap_original do |original, **dados|
        raise ActiveRecord::RecordNotDestroyed, 'Failed to destroy Contact' if dados[:contact_ids] == [bruno.id]

        original.call(**dados)
      end
      rastreador = o_rastreador_recebe(ActiveRecord::RecordNotDestroyed)

      expect(apagar).to eq(apagadas: 2, de_fora: [de_fora(bruno, 'erro')])
      expect(account.contacts.pluck(:id)).to eq([bruno.id])
      expect(rastreador).to have_received(:capture_exception).once
    end

    it 'conta como apagada quem outra pessoa já tinha apagado no meio do caminho' do
      allow(Contacts::BulkDeleteService).to receive(:new).and_wrap_original do |original, **dados|
        Contact.where(id: carla.id).delete_all if dados[:contact_ids] == [ana.id]
        original.call(**dados)
      end

      expect(apagar).to eq(apagadas: 3, de_fora: [])
    end
  end
end

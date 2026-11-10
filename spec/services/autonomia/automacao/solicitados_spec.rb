require 'rails_helper'

# G22 (#2414, exemplo 8, passo 9): o RH de cada empresa e quem ainda falta mandar documento. A seleção `solicitante_de`
# do contato.recorrente, o valor `contato.solicitados_faltando` e o que o salvar recusa.
RSpec.describe Autonomia::Automacao::Solicitados, :automacao_motor do
  around { |exemplo| with_modified_env(CRM_KANBAN_ENABLED: 'true') { exemplo.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Inclusão de vidas') }
  let(:funil) { funil_e_etapa.first }
  let(:documentos) { funil_e_etapa.last }
  let(:enviar) { create_crm_stage(account: account, pipeline: funil, name: 'Enviar à operadora') }
  let(:acme) { create(:company, account: account, name: 'Acme') }
  let(:marta) { create(:contact, account: account, name: 'Marta', company_id: acme.id) }
  let(:condicao) { { 'funil_id' => funil.id, 'faltando' => %w[rg cpf comprovante] } }
  let(:contexto_do_admin) { { user: admin, account: account, account_user: account.account_users.find_by(user: admin) } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_gatilhos')
    { 'rg' => 'RG', 'cpf' => 'CPF', 'comprovante' => 'comprovante' }.each do |chave, rotulo|
      create(:custom_attribute_definition, account: account, attribute_key: chave, attribute_display_name: rotulo,
                                           attribute_model: 'card_attribute', attribute_display_type: 'checkbox')
    end
  end

  def pedido(nome, marcados = {}, solicitante: marta, etapa: documentos, **atributos)
    funcionario = create(:contact, account: account, name: nome, company_id: solicitante.company_id)
    account.crm_cards.create!(pipeline: etapa.pipeline, stage: etapa, title: "Inclusão de #{nome}", currency: 'BRL', contact: funcionario,
                              solicitante: solicitante, custom_attributes: marcados, **atributos)
  end

  def gatilho(selecao: { 'solicitante_de' => condicao }) = { 'tipo' => 'contato.recorrente', 'selecao' => selecao }
  def selecao(**) = Autonomia::Automacao::Tempo::Selecao.new(account, gatilho(**))

  describe 'os pendentes' do
    it 'só o card aberto do funil, com solicitante e algum campo sem marcar', :aggregate_failures do
      falta = pedido('Ana Souza', { 'rg' => true })
      pedido('Bruno Lima', { 'rg' => true, 'cpf' => true, 'comprovante' => true })
      pedido('Perdido').update!(status: :lost)
      account.crm_cards.create!(pipeline: funil, stage: documentos, title: 'Sem solicitante', currency: 'BRL')
      outro_funil = create_crm_pipeline(account: account, user: admin, name: 'Vendas').last
      pedido('Outro funil', etapa: outro_funil)

      expect(described_class.new(account, condicao).pendentes).to eq([falta])
    end

    it 'com a etapa, só os cards dela; o "true" gravado como texto também conta como marcado', :aggregate_failures do
      na_etapa = pedido('Ana Souza', { 'rg' => 'true' })
      bruno = pedido('Bruno Lima', etapa: enviar)

      expect(described_class.new(account, condicao.merge('etapa_id' => documentos.id)).pendentes).to eq([na_etapa])
      expect(described_class.new(account, condicao.merge('faltando' => %w[rg])).pendentes).to eq([bruno])
    end

    it 'sem campo ou sem funil, ninguém (nunca a conta inteira)' do
      pedido('Ana Souza')

      expect(described_class.new(account, condicao.merge('faltando' => [])).pendentes).to be_empty
      expect(described_class.new(account, condicao.except('funil_id')).pendentes).to be_empty
    end

    # Qualidade: a chave vai como parâmetro, nunca no texto do SQL.
    it 'chave maliciosa não pega ninguém nem mexe no banco' do
      pedido('Ana Souza', { 'rg' => true, 'cpf' => true, 'comprovante' => true })
      maliciosas = ["rg') OR 1=1 --", "'; DROP TABLE crm_cards; --"]

      expect(described_class.new(account, condicao.merge('faltando' => maliciosas)).pendentes.count).to eq(1)
      expect(account.crm_cards.count).to eq(1)
    end
  end

  describe 'a seleção do contato.recorrente' do
    it 'pega o RH com pedido pendente e deixa de fora o RH com tudo completo', :aggregate_failures do
      pedido('Ana Souza', { 'rg' => true })
      beta = create(:company, account: account, name: 'Beta')
      joao = create(:contact, account: account, name: 'João', company_id: beta.id)
      pedido('Elias', { 'rg' => true, 'cpf' => true, 'comprovante' => true }, solicitante: joao)

      expect(selecao.escopo.pluck(:id)).to eq([marta.id])
      expect(selecao.escopo_para(contexto_do_admin, pergunta: :update?).pluck(:id)).to eq([marta.id])
    end

    # "Para cada empresa": duas pessoas do RH da mesma empresa recebem um aviso só, quem fez o pedido pendente mais novo.
    it 'um RH por empresa; o solicitante sem empresa responde pelos pedidos dele', :aggregate_failures do
      paulo = create(:contact, account: account, name: 'Paulo', company_id: acme.id)
      sem_empresa = create(:contact, account: account, name: 'Rita')
      pedido('Diego', solicitante: paulo)
      pedido('Ana Souza')
      pedido('Fábio', solicitante: sem_empresa)

      expect(selecao.escopo.pluck(:id)).to contain_exactly(marta.id, sem_empresa.id)
      expect(described_class.new(account, condicao).texto(marta)).to eq('Diego (RG, CPF, comprovante); Ana Souza (RG, CPF, comprovante)')
      expect(described_class.new(account, condicao).texto(sem_empresa)).to eq('Fábio (RG, CPF, comprovante)')
    end

    it 'junto com outra condição do contato, valem as duas' do
      create(:label, account: account, title: 'rh')
      pedido('Ana Souza')

      expect(selecao(selecao: { 'solicitante_de' => condicao, 'etiqueta' => 'rh' }).escopo).to be_empty
      marta.update!(label_list: ['rh'])
      expect(selecao(selecao: { 'solicitante_de' => condicao, 'etiqueta' => 'rh' }).escopo.pluck(:id)).to eq([marta.id])
    end

    # Parecer do Funções: o RH só é pego por card que quem ligou vê, e o texto só lista esses cards.
    it 'quem ligou numa função com 1 caixa: o card da outra caixa não seleciona nem aparece no texto', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      permissoes = %w[automation_manage conversation_manage contact_view contact_manage crm_view crm_manage_cards]
      funcao = create(:custom_role, account: account, permissions: permissoes)
      account_user = account.account_users.find_by(user: agente)
      account_user.update!(custom_role: funcao)
      caixa = create(:inbox, account: account)
      create(:inbox_member, user: agente, inbox: caixa)
      contexto = { user: agente, account: account, account_user: account_user }
      pedido('Escondido', inbox: create(:inbox, account: account))

      expect(selecao.escopo_para(contexto, pergunta: :update?)).to be_empty
      expect(selecao.quantos_para(contexto)).to eq(0)

      pedido('Ana Souza', { 'rg' => true }, inbox: caixa)
      expect(selecao.escopo_para(contexto, pergunta: :update?).pluck(:id)).to eq([marta.id])
      expect(described_class.texto_para(marta, account_user, condicao)).to eq('Ana Souza (CPF, comprovante)')
      expect(described_class.texto_para(marta, account.account_users.find_by(user: admin), condicao))
        .to eq('Escondido (RG, CPF, comprovante); Ana Souza (CPF, comprovante)')
    end
  end

  describe 'o valor contato.solicitados_faltando' do
    let(:valores) { Autonomia::Automacao::Valores }

    it 'lê da seleção do gatilho da execução, sem quebra de linha; sem execução, vazio', :aggregate_failures do
      pedido("Ana\nSouza", { 'rg' => true })
      pedido('Carla Dias')
      semanal = gatilho.merge('frequencia' => 'semanal', 'dia_da_semana' => 5, 'hora' => 9)
      definicao = automacao_ligada(account, admin, [esperar_passo('p1')], gatilho: semanal)
      execucao = instance_double(Autonomia::Automacao::Execucao, versao: definicao.versao_ativa)
      contexto = Autonomia::Automacao::Contexto.de(marta, execucao: execucao)

      expect(valores.new(alvo: contexto, quem: admin).ler('contato.solicitados_faltando'))
        .to eq('Ana Souza (CPF, comprovante); Carla Dias (RG, CPF, comprovante)')
      expect(valores.new(alvo: marta, quem: admin).ler('contato.solicitados_faltando')).to be_nil
      expect(valores.new(alvo: contexto, quem: nil).ler('contato.solicitados_faltando')).to be_nil
    end

    it 'o catálogo oferece o valor só no contato.recorrente' do
      item = Autonomia::Automacao::CatalogoDeValores.todos.find { |valor| valor['caminho'] == 'contato.solicitados_faltando' }

      expect(item).to include('base' => 'contato', 'so_nos_gatilhos' => ['contato.recorrente'],
                              'frase' => 'AUTOMACAO_LIVRE.VALORES.CONTATO_SOLICITADOS_FALTANDO')
    end
  end

  describe 'o salvar' do
    let(:account_user) { account.account_users.find_by(user: admin) }

    def problemas(receita) = Autonomia::Automacao::Receita.new(receita, conta: account, account_user: account_user).problemas

    def receita(selecao: { 'solicitante_de' => condicao }, tipo: 'contato.recorrente')
      { 'gatilho' => { 'tipo' => tipo, 'frequencia' => 'semanal', 'dia_da_semana' => 5, 'hora' => 9, 'selecao' => selecao },
        'passos' => [mensagem_passo('aviso', 'Faltam: ', { '$valor' => 'contato.solicitados_faltando' })] }
    end

    # Sem gravador, card nenhum teria solicitante, a condição nunca pegaria ninguém e o aviso de sexta pularia toda
    # semana sem mandar nada: o salvar recusa. O "para cada item" (G24) é o gravador de hoje.
    it 'o "para cada item" grava o solicitante; sem ele, recusa a condição solicitante_de (e só ela)', :aggregate_failures do
      expect(described_class::GRAVADORES).to eq(%w[para_cada])
      stub_const('Autonomia::Automacao::Solicitados::GRAVADORES', [])
      expect(described_class.gravado?).to be(false)
      frase = I18n.t('autonomia.automacao.receita.solicitante_sem_gravador')

      expect(problemas(receita)).to eq([frase])
      expect(problemas(receita(selecao: { 'solicitante_de' => condicao.merge('funil_id' => 0) }))).to eq([frase])
    end

    describe 'com o passo que grava o solicitante (o "para cada item" da G24)' do
      it 'aceita o valor no contato.recorrente com solicitante_de' do
        expect(problemas(receita)).to be_empty
      end

      it 'recusa o valor sem a condição solicitante_de ou fora do contato.recorrente', :aggregate_failures do
        create(:label, account: account, title: 'rh')
        frase = I18n.t('autonomia.automacao.receita.solicitados_so_no_recorrente', passo: 'aviso', caminho: 'contato.solicitados_faltando')

        expect(problemas(receita(selecao: { 'etiqueta' => 'rh' }))).to include(frase)
        conversa = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => receita['passos'] }
        expect(problemas(conversa)).to include(frase)
      end

      it 'recusa campo que não é de marcar do card, funil de fora e etapa de outro funil', :aggregate_failures do
        create(:custom_attribute_definition, account: account, attribute_key: 'cpf_do_contato', attribute_display_name: 'CPF',
                                             attribute_model: 'contact_attribute', attribute_display_type: 'checkbox')
        vendas_etapa = create_crm_pipeline(account: account, user: admin, name: 'Vendas').last
        texto = ->(chave, **valores) { I18n.t("autonomia.automacao.receita.#{chave}", **valores) }

        expect(problemas(receita(selecao: { 'solicitante_de' => condicao.merge('faltando' => %w[rg cpf_do_contato]) })))
          .to include(texto.call(:faltando_de_fora, campo: 'cpf_do_contato'))
        expect(problemas(receita(selecao: { 'solicitante_de' => condicao.merge('funil_id' => 0) })))
          .to include(texto.call(:funil_de_fora, id: 0))
        expect(problemas(receita(selecao: { 'solicitante_de' => condicao.merge('etapa_id' => vendas_etapa.id) })))
          .to include(texto.call(:etapa_de_fora, id: vendas_etapa.id))
      end

      it 'o esquema pede o funil e pelo menos um campo', :aggregate_failures do
        expect(Autonomia::Automacao::Receita.esquema_valido?(receita)).to be(true)
        expect(Autonomia::Automacao::Receita.esquema_valido?(receita(selecao: { 'solicitante_de' => condicao.merge('faltando' => []) })))
          .to be(false)
        expect(Autonomia::Automacao::Receita.esquema_valido?(receita(selecao: { 'solicitante_de' => condicao.except('funil_id') })))
          .to be(false)
        selecao_do_card = { 'funil_id' => funil.id, 'solicitante_de' => condicao }
        expect(problemas(receita(tipo: 'card.recorrente', selecao: selecao_do_card))).to include(
          I18n.t('autonomia.automacao.receita.selecao_de_outro_alvo', condicoes: 'solicitante_de')
        )
      end
    end
  end

  describe 'o contato' do
    it 'apagado, o card fica sem solicitante; mesclado, o solicitante passa para o que fica', :aggregate_failures do
      card = pedido('Ana Souza')
      outro = create(:contact, account: account, name: 'Marta Silva')
      ContactMergeAction.new(account: account, base_contact: outro, mergee_contact: marta).perform

      expect(card.reload.solicitante_contact_id).to eq(outro.id)
      outro.destroy!
      expect(card.reload.solicitante_contact_id).to be_nil
    end

    it 'o solicitante de outra conta é recusado no card' do
      card = pedido('Ana Souza')
      card.solicitante = create(:contact)

      expect(card).not_to be_valid
    end
  end
end

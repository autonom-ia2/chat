require 'rails_helper'

# G49: o registro que um passo criou nesta execução vira valor (`criado.<passo>`) e alvo dos passos seguintes.
# - exemplo 6 (automação no contato, pelo aniversário): o "criar card" do passo 3 abre o card, e os passos 5 e 6 gravam
#   nesse card, que o gatilho do contato não lê (`card.id` não existe no contato);
# - exemplo 11 (automação na conversa da Maria): o `POST contacts` cria o João, o "criar card" abre o card dele, e a ação
#   grava nele "indicado por" com o id da Maria, que só a execução da Maria lê.
RSpec.describe Autonomia::Automacao::RegistroCriado, :automacao_motor do
  include ActiveJob::TestHelper

  around { |example| with_modified_env(CRM_KANBAN_ENABLED: 'true') { example.run } }

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:funil_e_etapa) { create_crm_pipeline(account: account, user: admin, name: 'Aniversário') }
  let(:funil) { funil_e_etapa.first }
  let(:etapa) { funil_e_etapa.last }
  let(:frase) { 'autonomia.automacao.receita' }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos', 'automacao_mensagens')
    create(:custom_attribute_definition, account: account, attribute_key: 'presente', attribute_display_name: 'Presente',
                                         attribute_model: :card_attribute, attribute_display_type: :text)
    create(:custom_attribute_definition, account: account, attribute_key: 'indicado_por', attribute_display_name: 'Indicado por',
                                         attribute_model: :card_attribute, attribute_display_type: :number)
    create(:custom_attribute_definition, account: account, attribute_key: 'aniversario', attribute_display_name: 'Aniversário',
                                         attribute_model: :contact_attribute, attribute_display_type: :date)
  end

  after { Current.reset }

  def card(id, **extra) = { 'id' => id, 'tipo' => 'card', 'etapa_id' => etapa.id, **extra }

  def no_card(id, caminho, atributos)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'PATCH crm/cards/:id', 'descricao' => 'Gravar no card',
      'caminho' => { 'id' => { '$valor' => caminho } }, 'corpo' => { 'card' => { 'custom_attributes' => atributos } } }
  end

  def criar_contato(id)
    { 'id' => id, 'tipo' => 'acao', 'acao' => 'POST contacts', 'descricao' => 'Criar o contato do amigo',
      'corpo' => { 'name' => 'João', 'phone_number' => '+5511900000012' } }
  end

  def receita(gatilho, *passos) = { 'gatilho' => gatilho, 'passos' => passos }

  def aniversario = { 'tipo' => 'contato.data', 'campo' => 'aniversario', 'dias' => 0, 'quando' => 'depois', 'hora' => 9 }

  def problemas(conteudo) = Autonomia::Automacao::Receita.new(conteudo, conta: account, account_user: nil).problemas

  def rodar(alvo, gatilho, passos, chave:)
    definicao = automacao_ligada(account, admin, passos, gatilho: gatilho)
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) do
      Autonomia::Automacao::Partida.new(definicao: definicao, alvo: alvo, chave_gatilho: chave).call
    end
  end

  def historico(execucao) = Autonomia::Automacao::Registro.where(execucao: execucao).order(:id).pluck(:passo, :resultado, :motivo)

  describe 'ao salvar' do
    it 'o gatilho do contato não lê card.id, mas lê o card que o passo criou', :aggregate_failures do
      expect(problemas(receita(aniversario, card('p3'), no_card('p6', 'card.id', { 'presente' => 'hidratação' }))))
        .to eq([I18n.t("#{frase}.valor_fora_do_alvo", passo: 'p6', caminho: 'card.id')])
      expect(problemas(receita(aniversario, card('p3'), no_card('p6', 'criado.p3', { 'presente' => 'hidratação' })))).to be_empty
    end

    it 'recusa o registro de um passo que vem depois, que não cria ou que não existe', :aggregate_failures do
      gravar = no_card('p6', 'criado.p3', { 'presente' => 'hidratação' })
      nota = { 'id' => 'p2', 'tipo' => 'parar' }

      expect(problemas(receita(aniversario, gravar, card('p3'))))
        .to eq([I18n.t("#{frase}.criado_depois", passo: 'p6', caminho: 'criado.p3')])
      expect(problemas(receita(aniversario, nota, no_card('p6', 'criado.p2', { 'presente' => 'x' }))))
        .to eq([I18n.t("#{frase}.criado_sem_passo", passo: 'p6', caminho: 'criado.p2')])
      expect(problemas(receita(aniversario, no_card('p6', 'criado.p9', { 'presente' => 'x' }))))
        .to eq([I18n.t("#{frase}.criado_sem_passo", passo: 'p6', caminho: 'criado.p9')])
    end

    it 'o contato do "criar card" só aceita um contato criado: o card criado não serve', :aggregate_failures do
      no_criado = receita({ 'tipo' => 'conversa.resolvida' }, criar_contato('p3a'), card('p3b', 'contato' => { '$valor' => 'criado.p3a' }))
      no_card_criado = receita({ 'tipo' => 'conversa.resolvida' }, card('p3a'), card('p3b', 'contato' => { '$valor' => 'criado.p3a' }))

      expect(Autonomia::Automacao::Receita.esquema_valido?(no_criado)).to be(true)
      expect(problemas(no_criado)).to be_empty
      expect(problemas(no_card_criado)).to eq([I18n.t("#{frase}.criado_sem_passo", passo: 'p3b', caminho: 'criado.p3a')])
    end

    it 'a filha do "em outro registro" não lê o que a mãe criou: só vale na execução que criou' do
      ramo = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'registro' => { 'de' => 'cards_do_contato' },
               'passos' => [no_card('dentro', 'criado.p3', { 'presente' => 'x' })] }

      expect(problemas(receita({ 'tipo' => 'conversa.resolvida' }, card('p3'), ramo)))
        .to eq([I18n.t("#{frase}.criado_sem_passo", passo: 'dentro', caminho: 'criado.p3')])
    end

    it 'o "em outro registro" no card criado lê o card e pode abrir a conversa pela caixa da conversa nova', :aggregate_failures do
      caixa = create_crm_whatsapp_api_inbox(account: account, members: [admin])
      ramo = { 'id' => 'outro', 'tipo' => 'em_outro_registro', 'registro' => { 'de' => 'criado_no_passo', 'passo' => 'p3' },
               'passos' => [{ 'id' => 'oi', 'tipo' => 'mensagem', 'texto' => ['Card ', { '$valor' => 'card.titulo' }] }] }
      conteudo = receita({ 'tipo' => 'conversa.resolvida', 'conversa_nova' => { 'caixa_id' => caixa.id } }, card('p3'), ramo)

      expect(Autonomia::Automacao::Receita.esquema_valido?(conteudo)).to be(true)
      expect(problemas(conteudo)).to be_empty
      expect(Autonomia::Automacao::EmOutroRegistro.de_funil?(ramo, conteudo)).to be(true)
    end

    # O contato do campo só vem de um campo do card do tipo Contato (decisão 16); no gatilho de conversa, o card dela.
    it 'no gatilho de conversa, a caixa da conversa nova só vale com o ramo no registro criado, não no contato do campo' do
      caixa = create_crm_whatsapp_api_inbox(account: account, members: [admin])
      create(:custom_attribute_definition, account: account, attribute_key: 'quem_indicou', attribute_display_name: 'Quem indicou',
                                           attribute_model: :card_attribute, attribute_display_type: :contato)
      campo = { '$valor' => 'card.atributos.quem_indicou' }
      ramo = { 'id' => 'outro', 'tipo' => 'em_outro_registro',
               'registro' => { 'de' => 'contato_do_campo', 'campo' => campo, 'usar' => 'contato' },
               'passos' => [{ 'id' => 'oi', 'tipo' => 'mensagem', 'texto' => ['Oi'] }] }
      conteudo = receita({ 'tipo' => 'conversa.resolvida', 'conversa_nova' => { 'caixa_id' => caixa.id } }, ramo)

      expect(problemas(conteudo)).to eq([I18n.t("#{frase}.conversa_nova_sem_alvo")])
    end
  end

  describe 'ao rodar' do
    # Exemplo 6, passos 3, 5 e 6: a automação roda no contato e grava no card que ela mesma criou.
    it 'exemplo 6: na automação do contato, grava no card que o passo criou', :aggregate_failures do
      bia = create(:contact, account: account, name: 'Bia')

      execucao = rodar(bia, aniversario, [card('p3'), no_card('p6', 'criado.p3', { 'presente' => 'hidratação de presente' })],
                       chave: 'contato.data')

      criado = funil.cards.sole
      expect(criado).to have_attributes(contact_id: bia.id, stage_id: etapa.id)
      expect(criado.reload.custom_attributes).to include('presente' => 'hidratação de presente')
      expect(historico(execucao)).to eq([['p3', 'ok', nil], ['p6', 'ok', nil]])
      expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p3').dados['criado'])
        .to eq('tipo' => 'Crm::Card', 'id' => criado.id)
    end

    # Exemplo 11, passo 3: cria o João, o card dele e grava nele quem o indicou (o id da Maria, o contato do alvo).
    it 'exemplo 11: cria o contato, o card dele e grava quem indicou', :aggregate_failures do
      maria = create(:contact, account: account, name: 'Maria')
      conversa = create(:conversation, account: account, contact: maria, status: :open)
      passos = [criar_contato('p3a'), card('p3b', 'contato' => { '$valor' => 'criado.p3a' }),
                no_card('p3c', 'criado.p3b', { 'indicado_por' => { '$valor' => 'contato.id' } })]

      execucao = rodar(conversa, { 'tipo' => 'conversa.resolvida' }, passos, chave: 'conversa.resolvida')

      joao = account.contacts.find_by!(name: 'João')
      card_do_joao = funil.cards.sole
      expect(card_do_joao).to have_attributes(contact_id: joao.id, conversation_id: nil)
      expect(card_do_joao.reload.custom_attributes).to include('indicado_por' => maria.id)
      expect(historico(execucao)).to eq([['p3a', 'ok', nil], ['p3b', 'ok', nil], ['p3c', 'ok', nil]])
      expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p3a').dados['criado'])
        .to eq('tipo' => 'Contact', 'id' => joao.id)
    end

    it 'o passo que não criou (o card já existia) deixa o valor vazio, e quem lê pula com faltou_valor', :aggregate_failures do
      bia = create(:contact, account: account, name: 'Bia')
      account.crm_cards.create!(pipeline: funil, stage: etapa, title: 'Já tinha', contact: bia, currency: 'BRL')

      execucao = rodar(bia, aniversario, [card('p3'), no_card('p6', 'criado.p3', { 'presente' => 'x' })], chave: 'contato.data')

      expect(historico(execucao)).to eq([%w[p3 pulado card_ja_existe], %w[p6 pulado faltou_valor]])
    end

    # O laço que repete passos (#2791) passa pelo mesmo passo de novo: vale a última passagem, e a que pulou lê vazio.
    it 'vale a última passagem do passo: criou e depois pulou, lê vazio (nunca o id antigo)', :aggregate_failures do
      bia = create(:contact, account: account, name: 'Bia')
      definicao = automacao_ligada(account, admin, [card('p3')], gatilho: aniversario)
      execucao = Autonomia::Automacao::Execucao.create!(account: account, automacao: definicao, versao: definicao.versao_ativa,
                                                        alvo: bia, chave_gatilho: 'contato.data', estado: 'concluida')
      registrar = lambda do |resultado, dados|
        Autonomia::Automacao::Registro.create!(account: account, automacao: definicao, execucao: execucao, passo: 'p3', resultado: resultado,
                                               dados: dados)
      end

      registrar.call('ok', { 'criado' => { 'tipo' => 'Crm::Card', 'id' => 41 } })
      expect(Autonomia::Automacao::Contexto.de(bia, execucao: execucao).criado('p3')).to eq(41)

      registrar.call('pulado', { 'card_id' => 41 })
      expect(Autonomia::Automacao::Contexto.de(bia, execucao: execucao).criado('p3')).to be_nil

      registrar.call('ok', { 'criado' => { 'tipo' => 'Crm::Card', 'id' => 42 } })
      expect(Autonomia::Automacao::Contexto.de(bia, execucao: execucao).criado('p3')).to eq(42)
    end

    it 'a ação que cria mais de um registro do tipo dá o primeiro criado, na ordem do caderno' do
      caderno = Autonomia::Guide::Execucao.abrir(account: account, user: admin)
      [7, 5].each_with_index do |id, ordem|
        caderno.mudancas.create!(passo: 0, ordem: ordem, tabela: 'contacts', record_type: 'Contact', record_id: id, operacao: 'create')
      end

      expect(described_class.do_caderno('POST contacts', caderno)).to eq('tipo' => 'Contact', 'id' => 7)
    end

    it 'o contato criado que quem ligou não alcança pausa a automação, sem criar o card' do
      allow(ContactPolicy).to receive(:new).and_wrap_original do |original, *args|
        original.call(*args).tap { |politica| allow(politica).to receive(:update?).and_return(false) }
      end
      maria = create(:contact, account: account, name: 'Maria')
      conversa = create(:conversation, account: account, contact: maria, status: :open)

      execucao = rodar(conversa, { 'tipo' => 'conversa.resolvida' },
                       [criar_contato('p3a'), card('p3b', 'contato' => { '$valor' => 'criado.p3a' })], chave: 'conversa.resolvida')

      expect([historico(execucao).last, funil.cards.count]).to eq([%w[p3b falhou quem_ligou_sem_acesso], 0])
    end
  end
end

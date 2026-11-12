require 'rails_helper'

# #2499: G10 (F8.7), a etiqueta posta ou tirada na conversa e no contato, e F8.3, a troca de quem atende a conversa (a
# pessoa ou o time). Tudo pela plataforma: a gravação despacha o evento no commit, o EventDispatcherJob entrega ao
# AutomacaoListener e a Partida abre a execução.
RSpec.describe 'Automação livre: etiqueta posta ou tirada e troca de quem atende a conversa', :automacao_motor do # rubocop:disable RSpec/DescribeClass
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }
  let(:contato) { conversa.contact }
  let(:execucoes) { Autonomia::Automacao::Execucao }

  before do
    ligar_motor(account)
    account.enable_features!('automacao_gatilhos')
    %w[vip boleto].each { |titulo| create(:label, account: account, title: titulo) }
    conversa
    clear_enqueued_jobs
  end

  after { Current.reset }

  # Um job de cada vez, na ordem da fila: o job enfileirado dentro de outro só roda depois dele.
  def drenar
    drenados = [EventDispatcherJob, Autonomia::Automacao::AvancarJob]
    40.times do
      job = enqueued_jobs.find { |item| drenados.include?(item[:job]) }
      return unless job

      enqueued_jobs.delete(job)
      job[:job].perform_now(*ActiveJob::Arguments.deserialize(job[:args]))
    end
    raise 'a fila não esvaziou em 40 jobs'
  end

  def ligada(tipo, conta: account, autor: admin, **parametros)
    automacao_ligada(conta, autor, [esperar_passo('p1')], gatilho: { 'tipo' => tipo, **parametros.transform_keys(&:to_s) })
  end

  def fechar_todas = execucoes.update_all(estado: 'concluida', travada_em: nil, due_at: nil, finalizada_em: Time.current) # rubocop:disable Rails/SkipsModelValidations

  describe 'etiqueta na conversa' do
    it 'pôr a etiqueta começa só a automação dela', :aggregate_failures do
      vip = ligada('conversa.etiqueta_posta', etiqueta: 'vip')
      boleto = ligada('conversa.etiqueta_posta', etiqueta: 'boleto')
      tirada = ligada('conversa.etiqueta_tirada', etiqueta: 'vip')

      conversa.update_labels(%w[vip])
      drenar

      expect(execucoes.where(automacao: vip).sole).to have_attributes(alvo: conversa, chave_gatilho: 'conversa.etiqueta_posta')
      expect(execucoes.where(automacao: [boleto, tirada])).to be_empty
    end

    it 'tirar a etiqueta começa a automação de etiqueta tirada' do
      conversa.update_labels(%w[vip boleto])
      drenar
      tirada = ligada('conversa.etiqueta_tirada', etiqueta: 'vip')

      conversa.update_labels(%w[boleto])
      drenar

      expect(execucoes.where(automacao: tirada).sole.alvo).to eq(conversa)
    end

    # O EventDispatcherJob repete o evento com o mesmo instante: a marca barra a segunda execução, mesmo com a primeira
    # fechada.
    it 'o mesmo evento entregue 2 vezes abre 1 execução' do
      definicao = ligada('conversa.etiqueta_posta', etiqueta: 'vip')
      instante = Time.zone.now
      evento = Events::Base.new(Events::Types::CONVERSATION_UPDATED, instante,
                                conversation: conversa, changed_attributes: { 'label_list' => [[], %w[vip]] })

      Autonomia::AutomacaoListener.instance.conversation_updated(evento)
      fechar_todas
      Autonomia::AutomacaoListener.instance.conversation_updated(evento)

      expect(execucoes.where(automacao: definicao).sole.evento).to eq("conversa.etiqueta_posta:#{conversa.id}:vip:#{instante.utc.iso8601(6)}")
    end

    it 'a conversa no Spam não começa' do
      account.enable_features!('conversa_email_nova')
      caixa = create(:inbox, account: account, channel: create(:channel_email, account: account))
      no_spam = create(:conversation, account: account, inbox: caixa, status: :open)
      ConversaCanal::PastaDoEmail.create!(account: account, conversation: no_spam, pasta: 'spam')
      definicao = ligada('conversa.etiqueta_posta', etiqueta: 'vip')

      no_spam.update_labels(%w[vip])
      drenar

      expect(execucoes.where(automacao: definicao)).to be_empty
    end

    it 'a automação de outra conta, com a mesma etiqueta, não começa' do
      outra = create(:account)
      ligar_motor(outra)
      create(:label, account: outra, title: 'vip')
      # O autor da versão é da conta da automação (Versao valida); o admin desta conta não serve lá.
      de_fora = ligada('conversa.etiqueta_posta', conta: outra, autor: create(:user, account: outra, role: :administrator), etiqueta: 'vip')

      conversa.update_labels(%w[vip])
      drenar

      expect(execucoes.where(automacao: de_fora)).to be_empty
    end
  end

  describe 'etiqueta no contato' do
    it 'pôr a etiqueta no contato começa no contato' do
      definicao = ligada('contato.etiqueta_posta', etiqueta: 'vip')

      contato.update_labels(%w[vip])
      drenar

      expect(execucoes.where(automacao: definicao).sole.alvo).to eq(contato)
    end

    it 'sem a flag dos gatilhos, o de contato não começa' do
      definicao = ligada('contato.etiqueta_posta', etiqueta: 'vip')
      account.disable_features!('automacao_gatilhos')

      contato.update_labels(%w[vip])
      drenar

      expect(execucoes.where(automacao: definicao)).to be_empty
    end

    # A importação da base de campanha grava com os eventos de contato desligados (CampaignImports::SuppressedContactEvents).
    it 'a gravação com os eventos de contato desligados (importação) não começa' do
      definicao = ligada('contato.etiqueta_posta', etiqueta: 'vip')

      Current.suppress_contact_events = true
      contato.update_labels(%w[vip])
      Current.suppress_contact_events = nil
      drenar

      expect(execucoes.where(automacao: definicao)).to be_empty
    end
  end

  # Autonomia::Automacao::EtiquetaDoGatilho: o gatilho guarda o nome; mexer na etiqueta da conta não o deixa calado.
  describe 'etiqueta da conta renomeada ou apagada' do
    let(:vip) { account.labels.find_by!(title: 'vip') }

    def renomear(etiqueta, para)
      perform_enqueued_jobs(only: Labels::UpdateJob) { etiqueta.update!(title: para) }
      drenar
    end

    it 'renomear a etiqueta da conta não começa posta nem tirada, na conversa e no contato' do
      definicoes = %w[conversa.etiqueta_posta conversa.etiqueta_tirada contato.etiqueta_posta contato.etiqueta_tirada]
                   .map { |tipo| ligada(tipo, etiqueta: 'vip') }
      conversa.update_labels(%w[vip])
      contato.update_labels(%w[vip])
      drenar

      expect { renomear(vip, 'cliente-vip') }.not_to(change { execucoes.where(automacao: definicoes).count })
    end

    it 'renomear leva o nome novo ao gatilho, numa versão nova, e a automação segue ligada por quem ligou', :aggregate_failures do
      definicao = ligada('conversa.etiqueta_posta', etiqueta: 'vip')
      outra = ligada('conversa.etiqueta_posta', etiqueta: 'boleto')
      versao_da_outra = outra.versao_ativa_id

      renomear(vip, 'cliente-vip')

      expect(definicao.reload.versao_ativa.receita['gatilho']).to include('etiqueta' => 'cliente-vip')
      expect(definicao.versao_ativa).to have_attributes(numero: 2, autor_id: nil)
      expect(definicao).to have_attributes(ativa: true, ligada_por_id: admin.id)
      expect(outra.reload.versao_ativa_id).to eq(versao_da_outra)

      conversa.update_labels(%w[cliente-vip])
      drenar

      expect(execucoes.where(automacao: definicao).sole.alvo).to eq(conversa)
    end

    it 'apagar a etiqueta desliga a automação ligada, e religar diz que a etiqueta não existe', :aggregate_failures do
      definicao = ligada('contato.etiqueta_tirada', etiqueta: 'vip')
      outra = ligada('conversa.etiqueta_posta', etiqueta: 'boleto')

      vip.destroy!
      Labels::RemoveAssociationsJob.perform_now(label_title: 'vip', account_id: account.id, label_deleted_at: Time.current)

      expect([definicao.reload.ativa, outra.reload.ativa]).to eq([false, true])
      recusa = definicao.assumir_e_religar!(admin, versao_id: definicao.versao_ativa_id)
      expect(recusa.problemas).to include(I18n.t('autonomia.automacao.receita.etiqueta_de_fora', etiqueta: 'vip'))
    end

    it 'a etiqueta recriada com o mesmo nome antes do job não desliga nada' do
      definicao = ligada('conversa.etiqueta_posta', etiqueta: 'vip')
      apagada_em = Time.current
      vip.destroy!
      create(:label, account: account, title: 'vip')

      Labels::RemoveAssociationsJob.perform_now(label_title: 'vip', account_id: account.id, label_deleted_at: apagada_em)

      expect(definicao.reload.ativa).to be(true)
    end
  end

  describe 'troca de quem atende a conversa' do
    it 'trocar a pessoa começa a troca de responsável, com a anterior na marca; o time não', :aggregate_failures do
      responsavel = ligada('conversa.responsavel_mudou')
      time = ligada('conversa.time_mudou')

      conversa.update!(assignee: admin)
      drenar

      expect(execucoes.where(automacao: responsavel).sole.evento).to start_with("conversa.responsavel_mudou:#{conversa.id}:0:")
      expect(execucoes.where(automacao: time)).to be_empty
    end

    it 'trocar o time começa a troca de time; a pessoa não', :aggregate_failures do
      responsavel = ligada('conversa.responsavel_mudou')
      time = ligada('conversa.time_mudou')

      conversa.update!(team: create(:team, account: account, allow_auto_assign: false))
      drenar

      expect(execucoes.where(automacao: time).sole.alvo).to eq(conversa)
      expect(execucoes.where(automacao: responsavel)).to be_empty
    end

    it 'a conversa que já nasce atribuída não é troca' do
      responsavel = ligada('conversa.responsavel_mudou')

      create(:conversation, account: account, assignee: admin, status: :open)
      drenar

      expect(execucoes.where(automacao: responsavel)).to be_empty
    end
  end

  describe 'ao salvar (Receita)' do
    def receita(gatilho) = { 'gatilho' => gatilho, 'passos' => [esperar_passo('p1')] }
    def problemas(gatilho) = Autonomia::Automacao::Receita.new(receita(gatilho), conta: account, account_user: nil).problemas
    def no_esquema?(gatilho) = Autonomia::Automacao::Receita.esquema_valido?(receita(gatilho))

    it 'aceita a etiqueta da conta, na conversa e no contato' do
      expect(%w[conversa.etiqueta_posta contato.etiqueta_tirada].flat_map { |tipo| problemas('tipo' => tipo, 'etiqueta' => 'vip') })
        .to be_empty
    end

    it 'recusa a etiqueta que não existe na conta' do
      expect(problemas('tipo' => 'conversa.etiqueta_posta', 'etiqueta' => 'sumiu'))
        .to eq([I18n.t('autonomia.automacao.receita.etiqueta_de_fora', etiqueta: 'sumiu')])
    end

    it 'o de contato pede a flag dos gatilhos; o de conversa, não', :aggregate_failures do
      account.disable_features!('automacao_gatilhos')

      expect(problemas('tipo' => 'contato.etiqueta_posta', 'etiqueta' => 'vip'))
        .to eq([I18n.t('autonomia.automacao.receita.gatilho_desligado')])
      expect(problemas('tipo' => 'conversa.etiqueta_posta', 'etiqueta' => 'vip')).to be_empty
      expect(problemas('tipo' => 'conversa.responsavel_mudou')).to be_empty
    end

    it 'o esquema pede a etiqueta no gatilho de etiqueta e a recusa nos outros', :aggregate_failures do
      expect(no_esquema?('tipo' => 'conversa.etiqueta_posta', 'etiqueta' => 'vip')).to be(true)
      expect(no_esquema?('tipo' => 'conversa.etiqueta_posta')).to be(false)
      expect(no_esquema?('tipo' => 'conversa.resolvida', 'etiqueta' => 'vip')).to be(false)
      expect(no_esquema?('tipo' => 'conversa.time_mudou')).to be(true)
    end
  end
end

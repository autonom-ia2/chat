require 'rails_helper'

# G52 (#2760): o passo "Pôr na lista de e-mail" põe o contato do alvo na lista (a etiqueta dela), como quem ligou.
RSpec.describe Autonomia::Automacao::PassoDeListaDeEmail, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:lista) { EmailList.criar(account: account, name: 'Dicas do mês') }
  let(:passo) { { 'id' => 'l1', 'tipo' => 'lista_de_email', 'lista_id' => lista.id } }
  let(:caixa) { create(:inbox, account: account) }
  let(:contato) { create(:contact, account: account, email: 'ana@exemplo.com') }
  let(:conversa) { create(:conversation, account: account, inbox: caixa, contact: contato) }

  around do |example|
    with_modified_env(CRM_KANBAN_ENABLED: 'true', EMAIL_CAMPAIGN_ENABLED: 'true') { example.run }
  end

  before { ligar_motor(account) }

  after { Current.reset }

  def frase(chave, **valores) = I18n.t("autonomia.automacao.receita.#{chave}", passo: 'l1', **valores)

  def problemas(passo_salvo = passo, quem: dona, gatilho: 'card.ganho')
    receita = { 'gatilho' => { 'tipo' => gatilho }, 'passos' => [passo_salvo] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  def executar(alvo = conversa, por: dona)
    execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, por, [passo]), account: account)
    described_class.new(execucao: execucao, passo: passo, alvo: alvo).executar
  end

  describe 'ao salvar' do
    it 'aceita a lista da conta no gatilho de card ganho (exemplo 20), de conversa e de contato' do
      account.enable_features!('automacao_gatilhos')

      expect(problemas).to be_empty
      expect(problemas(gatilho: 'conversa.resolvida')).to be_empty
    end

    it 'recusa no gatilho da conta, que roda sem contato' do
      allow(Autonomia::Automacao::Gatilhos).to receive(:da_conta?).and_return(true)
      allow(Autonomia::Automacao::Gatilhos).to receive(:do_card?).and_return(true)
      allow(Autonomia::Automacao::Gatilhos).to receive(:desligado).and_return(nil)

      expect(problemas(gatilho: 'conversa.resolvida')).to include(I18n.t('autonomia.automacao.receita.passo_pede_alvo', passo: 'l1'))
    end

    it 'recusa lista de outra conta, quem não gerencia campanhas e campanhas de e-mail desligadas' do
      outra = EmailList.criar(account: create(:account), name: 'Outra')
      agente = create(:user, account: account, role: :agent)

      expect(problemas(passo.merge('lista_id' => outra.id), gatilho: 'conversa.resolvida'))
        .to eq([frase(:lista_de_email_de_fora, id: outra.id)])
      expect(problemas(quem: agente, gatilho: 'conversa.resolvida')).to include(frase(:lista_de_email_sem_permissao))
      with_modified_env(EMAIL_CAMPAIGN_ENABLED: 'false') do
        expect(problemas(gatilho: 'conversa.resolvida')).to include(frase(:lista_de_email_desligada))
      end
    end

    it 'o esquema pede a lista' do
      sem_lista = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo.except('lista_id')] }

      expect(Autonomia::Automacao::Receita.esquema_valido?(sem_lista)).to be(false)
      expect(Autonomia::Automacao::Receita.esquema_valido?(sem_lista.merge('passos' => [passo]))).to be(true)
    end
  end

  describe 'ao rodar' do
    it 'põe a etiqueta da lista no contato da conversa, assinada pela automação, sem tirar as outras' do
      contato.update_labels(['cliente'])

      resultado = executar

      expect(resultado).to have_attributes(tipo: :ok, dados: { 'lista_id' => lista.id, 'contato_id' => contato.id })
      expect(contato.reload.label_list).to contain_exactly('cliente', 'lista-email-dicas-do-mes')
      expect(lista.contatos).to include(contato)
    end

    it 'contato que já está na lista pula' do
      contato.update_labels([lista.label.title])

      expect(executar).to have_attributes(tipo: :pulado, motivo: 'ja_na_lista')
    end

    it 'contato sem e-mail pula; contato que pediu para não receber entra mesmo assim (o envio confere)' do
      contato.update!(email: nil, phone_number: '+5511988887777')
      expect(executar).to have_attributes(tipo: :pulado, motivo: 'lista_contato_sem_email')

      contato.update!(email: 'ana@exemplo.com')
      contato.opt_out!(source: 'manual')
      expect(executar).to have_attributes(tipo: :ok)
      expect(lista.elegiveis).not_to include(contato)
    end

    it 'funciona com o contato como alvo' do
      expect(executar(contato).tipo).to eq(:ok)
    end

    it 'quem ligou sem campaign_manage: sem acesso, e nada muda' do
      automacao = automacao_ligada(account, dona, [passo])
      dona.account_users.find_by(account: account).update!(role: :agent)
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao, account: account)

      resultado = described_class.new(execucao: execucao, passo: passo, alvo: conversa).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_lista'])
      expect(contato.reload.label_list).to be_empty
    end

    it 'lista apagada depois de salvar pula com o motivo' do
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, dona, [passo]), account: account)
      lista.destroy!

      expect(described_class.new(execucao: execucao, passo: passo, alvo: conversa).executar)
        .to have_attributes(tipo: :pulado, motivo: 'lista_de_email_sumiu')
    end

    it 'pelo executor, num gatilho de conversa, sem a flag das mensagens' do
      automacao = automacao_ligada(account, dona, [passo])

      execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }

      expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'l1')).to have_attributes(resultado: 'ok')
      expect(execucao.reload.estado).to eq('concluida')
      expect(contato.reload.label_list).to include('lista-email-dicas-do-mes')
    end
  end
end

require 'rails_helper'

# #3100: o passo "Dar carimbos ou pontos" dá carimbos de presente ao contato do alvo, pelo cartão fidelidade da conta,
# como quem ligou (fidelidade_manage). Também os valores do cartão que a Automação lê do contato.
RSpec.describe Autonomia::Automacao::PassoDeDarCarimbos, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:inbox) { create_crm_whatsapp_api_inbox(account: account, members: [dona]) }
  let(:contato) { account.contacts.create!(name: 'Ana Albuquerino', phone_number: '+5511987654321') }
  let(:conversa) { create_crm_conversation(account: account, inbox: inbox, contact: contato) }
  let(:passo) { { 'id' => 'd1', 'tipo' => 'dar_carimbos', 'quantos' => 2, 'motivo' => 'aniversário' } }
  let!(:programa) do
    Fidelidade::Programa.create!(account: account, tipo: 'carimbos', a_cada_centavos: 5_000, ganha: 1, meta: 10,
                                 premio: 'Uma lavagem grátis', ligado: true, ligado_em: 1.day.ago)
  end

  before do
    ligar_motor(account)
    account.enable_features!('automacao_passos_novos')
  end

  after { Current.reset }

  def frase(chave) = I18n.t("autonomia.automacao.receita.fidelidade.#{chave}", passo: 'd1')

  def problemas(quem: dona, passo_salvo: passo)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo_salvo] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  def executar(alvo = conversa, por: dona, automacao: automacao_ligada(account, por, [passo]))
    execucao = Autonomia::Automacao::Execucao.new(automacao: automacao, account: account)
    described_class.new(execucao: execucao, passo: passo, acesso: Autonomia::Automacao::Acesso.new(automacao), alvo: alvo).executar
  end

  def saldo = Fidelidade::Saldo.find_by(programa_id: programa.id, contact_id: contato.id)&.saldo

  describe 'ao salvar' do
    it 'aceita com o cartão criado e quem pode mudar o cartão' do
      expect(problemas).to be_empty
    end

    it 'recusa sem cartão na conta e para quem não pode mudar o cartão', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)

      expect(problemas(quem: agente)).to include(frase(:sem_permissao))
      programa.destroy!
      expect(problemas).to include(frase(:sem_cartao))
    end

    it 'o esquema pede quantos, de 1 em diante, e o motivo cabe em 60 letras', :aggregate_failures do
      receita = ->(dado) { { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [dado] } }

      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo))).to be(true)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo.except('quantos')))).to be(false)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo.merge('quantos' => 0)))).to be(false)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo.merge('motivo' => 'a' * 61)))).to be(false)
    end

    it 'sem a flag dos passos novos, recusa como os outros passos novos' do
      account.disable_features!('automacao_passos_novos')

      expect(problemas).to include(I18n.t('autonomia.automacao.receita.passos_novos_desligados', passo: 'd1'))
    end
  end

  describe 'ao rodar' do
    it 'dá os carimbos de presente, com o motivo e a execução de origem' do
      resultado = executar

      expect(resultado).to have_attributes(tipo: :ok, dados: { 'contato_id' => contato.id, 'quantos' => 2, 'saldo' => 2 })
      movimento = Fidelidade::Movimento.find_by!(programa: programa, contact_id: contato.id)
      expect(movimento).to have_attributes(tipo: 'presente', quantos: 2, motivo: 'aniversário', origem_type: 'Autonomia::Automacao::Execucao')
      expect(saldo).to eq(2)
    end

    it 'com o contato como alvo também' do
      expect(executar(contato).tipo).to eq(:ok)
      expect(saldo).to eq(2)
    end

    it 'completou o cartão: dispara o gatilho "completou o cartão"' do
      Fidelidade::Carteira.new(programa, contato).entrar(tipo: 'presente', quantos: 9)
      allow(Fidelidade::CartaoCompleto).to receive(:avisar)

      executar

      expect(Fidelidade::CartaoCompleto).to have_received(:avisar).with(account, [[contato, an_instance_of(Fidelidade::Movimento)]])
    end

    # A automação foi salva com o cartão ligado; ele é pausado e depois apagado com ela já salva (salvar recusa sem cartão).
    it 'cartão pausado ou apagado: pula com o motivo, e ninguém recebe', :aggregate_failures do
      salva = automacao_ligada(account, dona, [passo])
      programa.update!(ligado: false)
      expect(executar(automacao: salva)).to have_attributes(tipo: :pulado, motivo: 'cartao_fidelidade_pausado')

      programa.destroy!
      expect(executar(automacao: salva)).to have_attributes(tipo: :pulado, motivo: 'sem_cartao_fidelidade')
      expect(Fidelidade::Movimento.count).to eq(0)
    end

    it 'quem ligou sem fidelidade_manage: sem acesso, e nada muda' do
      automacao = automacao_ligada(account, dona, [passo])
      dona.account_users.find_by(account: account).update!(role: :agent)
      execucao = Autonomia::Automacao::Execucao.new(automacao: automacao, account: account)

      resultado = described_class.new(execucao: execucao, passo: passo, acesso: Autonomia::Automacao::Acesso.new(automacao),
                                      alvo: conversa).executar

      expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_fidelidade'])
      expect(saldo).to be_nil
    end

    it 'pelo executor, num gatilho de conversa' do
      automacao = automacao_ligada(account, dona, [passo])

      execucao = perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }

      expect(Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'd1')).to have_attributes(resultado: 'ok')
      expect(saldo).to eq(2)
    end
  end

  describe 'no ensaio' do
    it 'diz quantos a pessoa tem e com quantos ficaria, sem gravar nada', :aggregate_failures do
      conversa
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }

      no, = Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: dona).resultado[:conversas].first[:passos]

      expect(no).to include(faria: 'dar_carimbos', dados: { quantos: 2, tem: 0, ficaria: 2, meta: 10, unidade: 'carimbos' })
      expect(Fidelidade::Movimento.count).to eq(0)
    end
  end

  describe 'os valores do cartão no contato' do
    def ler(caminho) = Autonomia::Automacao::Valores.new(alvo: conversa, quem: nil).ler(caminho)

    it 'lê o saldo, quantos faltam e o prêmio; sem cartão, vazios', :aggregate_failures do
      Fidelidade::Carteira.new(programa, contato).entrar(tipo: 'presente', quantos: 7)

      expect([ler('contato.fidelidade_saldo'), ler('contato.fidelidade_faltam'), ler('contato.fidelidade_premio')])
        .to eq([7, 3, 'Uma lavagem grátis'])

      Fidelidade::Movimento.delete_all
      Fidelidade::Saldo.delete_all
      programa.destroy!
      expect(ler('contato.fidelidade_saldo')).to be_nil
    end
  end
end

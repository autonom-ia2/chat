require 'rails_helper'

# #3100: o passo "Mandar cupom" acha ou sorteia o código do cupom para o contato do alvo e manda a mensagem com ele, como
# o passo "mensagem", com os dados do cupom no texto. Pede fidelidade_manage de quem salva e de quem ligou.
RSpec.describe Autonomia::Automacao::PassoDeMandarCupom, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account, locale: 'pt_BR') }
  let(:dona) { create(:user, account: account, role: :administrator) }
  let(:contato) { create(:contact, account: account, name: 'Ana Albuquerino') }
  let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }
  let(:agora) { Time.zone.parse('2026-11-23 12:00:00') }
  let!(:cupom) do
    Fidelidade::Cupom.create!(account: account, nome: 'Volta de dezembro', oferta_tipo: 'porcentagem', oferta_valor: 10,
                              moeda: 'BRL', prefixo: 'VOLTA', validade_dias: 15)
  end
  let(:passo) do
    { 'id' => 'c1', 'tipo' => 'mandar_cupom', 'cupom_id' => cupom.id,
      'texto' => ['Oi ', { '$valor' => 'contato.nome' }, '! O cupom ', { '$valor' => 'cupom.codigo' }, ' dá ',
                  { '$valor' => 'cupom.oferta' }, '. Vale até ', { '$valor' => 'cupom.vale_ate' }, '.'] }
  end

  before do
    travel_to(agora)
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_passos_novos')
  end

  after { Current.reset }

  def frase(chave) = I18n.t("autonomia.automacao.receita.fidelidade.#{chave}", passo: 'c1')

  def problemas(quem: dona, passo_salvo: passo)
    receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo_salvo] }
    Autonomia::Automacao::Receita.new(receita, conta: account, account_user: AccountUser.find_by(account: account, user: quem)).problemas
  end

  def rodar(automacao = automacao_ligada(account, dona, [passo]))
    perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(automacao, conversa) }
  end

  def executar(execucao = nil, passo_usado: passo)
    execucao ||= Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, dona, [passo_usado]), account: account)
    described_class.new(execucao: execucao, passo: passo_usado, alvo: conversa).executar
  end

  def registro(execucao) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'c1')

  def mandadas = conversa.messages.outgoing.where(private: false)

  describe 'ao salvar' do
    it 'aceita com o cupom da conta, o código no texto e quem pode mudar o cartão' do
      expect(problemas).to be_empty
    end

    it 'recusa quem não pode mudar o cartão, cupom de fora e texto sem o código', :aggregate_failures do
      agente = create(:user, account: account, role: :agent)
      de_fora = Fidelidade::Cupom.create!(account: create(:account), nome: 'De fora', oferta_tipo: 'presente', oferta_texto: 'Brinde',
                                          prefixo: 'FORA', validade_dias: 7)

      expect(problemas(quem: agente)).to include(frase(:sem_permissao_cupom))
      expect(problemas(passo_salvo: passo.merge('cupom_id' => de_fora.id))).to include(frase(:sem_cupom))
      expect(problemas(passo_salvo: passo.merge('texto' => ['Volte sempre!']))).to include(frase(:sem_codigo))
    end

    it 'o dado do cupom que não existe é recusado, e os do cupom só valem neste passo', :aggregate_failures do
      inventado = passo.merge('texto' => [*passo['texto'], { '$valor' => 'cupom.segredo' }])
      desconhecido = ->(id, caminho) { I18n.t('autonomia.automacao.receita.valor_desconhecido', passo: id, caminho: caminho) }

      expect(problemas(passo_salvo: inventado)).to include(desconhecido.call('c1', 'cupom.segredo'))
      expect(problemas(passo_salvo: mensagem_passo('m1', 'Seu cupom ', { '$valor' => 'cupom.codigo' })))
        .to include(desconhecido.call('m1', 'cupom.codigo'))
    end

    it 'o esquema pede o cupom e o texto' do
      receita = ->(dado) { { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [dado] } }

      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo))).to be(true)
      expect(Autonomia::Automacao::Receita.esquema_valido?(receita.call(passo.except('cupom_id')))).to be(false)
    end
  end

  describe 'ao rodar' do
    it 'pelo executor: sorteia o código, manda a mensagem com ele e marca o código como mandado', :aggregate_failures do
      execucao = rodar

      codigo = Fidelidade::CupomCodigo.find_by!(cupom: cupom, contact: contato)
      expect(mandadas.last.content).to eq("Oi Ana Albuquerino! O cupom #{codigo.codigo} dá 10% de desconto. Vale até 08/12.")
      expect(codigo).to have_attributes(enviado_em: agora, vale_ate: agora + 15.days, automacao_execucao_id: execucao.id)
      expect(registro(execucao)).to have_attributes(resultado: 'ok')
    end

    it 'mandar de novo manda o mesmo código, com a mesma validade', :aggregate_failures do
      execucao = rodar
      primeiro = Fidelidade::CupomCodigo.find_by!(cupom: cupom, contact: contato)

      travel 3.days
      resultado = executar(execucao)

      expect(resultado).to have_attributes(tipo: :ok, dados: include('cupom_id' => cupom.id))
      expect(Fidelidade::CupomCodigo.where(cupom: cupom, contact: contato).count).to eq(1)
      expect(primeiro.reload).to have_attributes(enviado_em: agora, vale_ate: agora + 15.days)
      expect(mandadas.last.content).to include(primeiro.codigo)
    end

    it 'código já usado ou vencido, cupom pausado ou que não existe: pula com o motivo, e nada sai', :aggregate_failures do
      codigo = Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: contato, codigo: 'VOLTA-7KD2',
                                               enviado_em: agora - 20.days, vale_ate: agora - 5.days)
      expect(executar).to have_attributes(tipo: :pulado, motivo: 'cupom_vencido')

      codigo.update!(vale_ate: agora + 1.day, usado_em: agora)
      expect(executar).to have_attributes(tipo: :pulado, motivo: 'cupom_ja_usado')

      cupom.update!(ligado: false)
      expect(executar).to have_attributes(tipo: :pulado, motivo: 'cupom_pausado')

      # O cupom some depois que a receita foi salva (salvar recusa cupom que não existe): a execução é de uma receita válida.
      salva = Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, dona, [passo]), account: account)
      expect(executar(salva, passo_usado: passo.merge('cupom_id' => 0))).to have_attributes(tipo: :pulado, motivo: 'sem_cupom')
      expect(mandadas).to be_empty
    end

    describe 'a marca de mandado' do
      let(:execucao) { Autonomia::Automacao::Execucao.new(automacao: automacao_ligada(account, dona, [passo]), account: account) }
      let(:passo_rodando) { described_class.new(execucao: execucao, passo: passo, alvo: conversa) }

      def codigo = Fidelidade::CupomCodigo.find_by!(cupom: cupom, contact: contato)

      it 'o código já vale quando a mensagem sai: falhar depois do envio não deixa o cliente com código que não existe' do
        na_hora = nil
        allow(passo_rodando).to receive(:mandar).and_wrap_original do |original, *args|
          na_hora = codigo.attributes.slice('enviado_em', 'vale_ate')
          original.call(*args)
        end

        expect(passo_rodando.executar.tipo).to eq(:ok)
        expect(na_hora).to eq('enviado_em' => agora, 'vale_ate' => agora + 15.days)
      end

      it 'a mensagem que não sai desfaz a marca: o código volta a não ter chegado', :aggregate_failures do
        allow(passo_rodando).to receive(:mandar).and_return(Autonomia::Automacao::PassoDeMensagem.pulado('fora_da_janela'))

        expect(passo_rodando.executar).to have_attributes(tipo: :pulado, motivo: 'fora_da_janela')
        expect(codigo).to have_attributes(enviado_em: nil, vale_ate: nil, automacao_execucao_id: nil)
      end

      it 'o envio que quebra desfaz a marca e o erro sobe', :aggregate_failures do
        allow(passo_rodando).to receive(:mandar).and_raise(StandardError, 'o canal caiu')

        expect { passo_rodando.executar }.to raise_error(StandardError, 'o canal caiu')
        expect(codigo).to have_attributes(enviado_em: nil, vale_ate: nil)
      end

      it 'mandar de novo e não sair não apaga o primeiro envio' do
        Fidelidade::CupomCodigo.create!(account: account, cupom: cupom, contact: contato, codigo: 'VOLTA-7KD2',
                                        enviado_em: agora - 2.days, vale_ate: agora + 13.days)
        allow(passo_rodando).to receive(:mandar).and_return(Autonomia::Automacao::PassoDeMensagem.pulado('fora_da_janela'))

        passo_rodando.executar

        expect(codigo).to have_attributes(enviado_em: agora - 2.days, vale_ate: agora + 13.days)
      end
    end

    it 'quem ligou sem fidelidade_manage: sem acesso, nada sai e nenhum código é sorteado', :aggregate_failures do
      automacao = automacao_ligada(account, dona, [passo])
      dona.account_users.find_by(account: account).update!(role: :agent)

      resultado = executar(Autonomia::Automacao::Execucao.new(automacao: automacao, account: account))

      expect([resultado.tipo, resultado.motivo]).to eq([:sem_acesso, 'quem_ligou_sem_permissao_fidelidade'])
      expect(mandadas).to be_empty
      expect(Fidelidade::CupomCodigo.count).to eq(0)
    end
  end

  describe 'no ensaio' do
    it 'diz qual cupom iria e se o código é novo, sem sortear nada', :aggregate_failures do
      conversa
      receita = { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => [passo] }

      no, = Autonomia::Automacao::Ensaio.new(receita: receita, conta: account, usuario: dona).resultado[:conversas].first[:passos]

      expect(no).to include(faria: 'mandar_cupom', dados: { cupom: 'Volta de dezembro', mesmo_codigo: false })
      expect(Fidelidade::CupomCodigo.count).to eq(0)
    end
  end
end

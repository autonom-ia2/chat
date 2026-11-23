require 'rails_helper'

# #3099 (F3 do épico #3095): duas versões da mensagem na Automação livre. O sorteio fixo por alvo, a versão 2 no lugar
# do texto e do modelo, o que zera o teste ao salvar, o que a Receita recusa e o envio de ponta a ponta no executor.
RSpec.describe Autonomia::Automacao::DuasVersoes, :automacao_motor do
  include ActiveJob::TestHelper

  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:regra) { { 'criterio' => 'respostas', 'divisao' => 50, 'espera' => 4 } }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
  end

  after { Current.reset }

  def com_versoes(texto2 = ['Olá! Tudo certo por aí?'], **regra_extra)
    mensagem_passo('p1', 'Oi, tudo bem?').merge('versoes' => regra.merge('texto' => texto2, 'modelo' => nil, **regra_extra.transform_keys(&:to_s)))
  end

  def linha(automacao) = Autonomia::Automacao::VersaoVencedora.find_by(automacao_id: automacao.id, passo: 'p1')

  # A frase da Receita para o passo p1, entre os erros da versão recusada.
  def recusa(chave)
    raise_error(ActiveRecord::RecordInvalid) do |erro|
      expect(erro.record.errors[:receita]).to include(I18n.t("autonomia.automacao.receita.#{chave}", passo: 'p1'))
    end
  end

  def salvar(automacao, passos)
    automacao.salvar_versao!(receita: { 'gatilho' => { 'tipo' => 'conversa.resolvida' }, 'passos' => passos }, autor: admin)
  end

  describe '.sorteio' do
    let(:alvos) { (1..200).map { |id| Conversation.new(id: id) } }

    it 'dá sempre a mesma versão ao mesmo alvo e reparte pela divisão', :aggregate_failures do
      metade = alvos.map { |alvo| described_class.sorteio(7, com_versoes, alvo) }
      mais_na_1 = alvos.map { |alvo| described_class.sorteio(7, com_versoes(divisao: 70), alvo) }

      expect(alvos.map { |alvo| described_class.sorteio(7, com_versoes, alvo) }).to eq(metade)
      expect(metade.count(1)).to be_between(80, 120)
      expect(mais_na_1.count(1)).to be_between(120, 160)
      expect(metade.zip(mais_na_1).select { |um, outro| um == 1 && outro == 2 }).to be_empty
    end
  end

  describe '.passo_da_versao' do
    let(:modelo) { { 'nome' => 'oi', 'idioma' => 'pt_BR', 'variaveis' => [] } }

    it 'a versão 1 é o passo sem `versoes`; a 2 troca o texto e o modelo', :aggregate_failures do
      passo = com_versoes.merge('modelo' => modelo)
      passo['versoes']['modelo'] = modelo.merge('nome' => 'ola')

      expect(described_class.passo_da_versao(passo, 1)).to eq(passo.except('versoes'))
      expect(described_class.passo_da_versao(passo, 2)).to include('texto' => ['Olá! Tudo certo por aí?'],
                                                                   'modelo' => modelo.merge('nome' => 'ola'))
      expect(described_class.passo_da_versao(com_versoes, 2)).not_to have_key('modelo')
      expect(described_class.passo_da_versao(com_versoes, 2)).not_to have_key('versoes')
    end
  end

  describe 'ao salvar a automação' do
    let(:automacao) { create(:autonomia_automacao, account: account) }

    it 'ligar as duas versões começa o teste; mudar só a regra não recomeça', :aggregate_failures do
      travel_to(2.days.ago) { salvar(automacao, [com_versoes]) }
      comeco = linha(automacao).teste_desde
      expect(comeco).to be_within(1.minute).of(2.days.ago)

      salvar(automacao, [com_versoes(criterio: 'eu_escolho', divisao: 70)])
      expect(linha(automacao).reload.teste_desde).to eq(comeco)
    end

    it 'mudar o texto de uma das versões recomeça o teste e tira a vencedora', :aggregate_failures do
      travel_to(2.days.ago) { salvar(automacao, [com_versoes]) }
      linha(automacao).update!(vencedora: 2, escolhida_por: 'sistema', escolhida_em: 1.day.ago)

      salvar(automacao, [com_versoes(['Olá! Posso ajudar?'])])

      atual = linha(automacao).reload
      expect(atual.teste_desde).to be_within(1.minute).of(Time.current)
      expect([atual.vencedora, atual.escolhida_por, atual.escolhida_em]).to eq([nil, nil, nil])
    end

    it 'recusa a versão 2 igual à 1, com a frase do passo' do
      expect { salvar(automacao, [com_versoes(['Oi, tudo bem?'])]) }.to recusa(:versoes_iguais)
    end

    it 'recusa a versão 2 vazia (o esquema pede texto)' do
      expect { salvar(automacao, [com_versoes([])]) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'confere os dados do texto da versão 2 pela régua de sempre' do
      expect { salvar(automacao, [com_versoes(['Olá, ', { '$valor' => 'nao.existe' }])]) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'recusa "mais compras" sem o CRM' do
      allow(Crm::Config).to receive(:enabled?).and_return(false)

      expect { salvar(automacao, [com_versoes(criterio: 'compras', espera: 24)]) }.to recusa(:versoes_sem_compras)
    end

    it 'recusa o modelo na versão 2 sem modelo na versão 1' do
      passo = com_versoes
      passo['versoes']['modelo'] = { 'nome' => 'ola', 'idioma' => 'pt_BR', 'variaveis' => [] }

      expect { salvar(automacao, [passo]) }.to recusa(:versoes_modelo_sobrando)
    end
  end

  describe 'no executor' do
    let(:contato) { create(:contact, account: account, name: 'Bruno') }
    let(:conversa) { create(:conversation, account: account, contact: contato, status: :open) }

    def comecar_e_rodar(definicao)
      perform_enqueued_jobs(only: Autonomia::Automacao::AvancarJob) { comecar(definicao, conversa) }
    end

    def registro(execucao) = Autonomia::Automacao::Registro.find_by!(execucao: execucao, passo: 'p1')

    it 'manda a versão sorteada do alvo, conta o envio e diz a versão no registro', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [com_versoes])
      versao = described_class.sorteio(definicao.id, com_versoes, conversa)
      execucao = comecar_e_rodar(definicao)

      texto = versao == 1 ? 'Oi, tudo bem?' : 'Olá! Tudo certo por aí?'
      expect(conversa.messages.outgoing.last.content).to eq(texto)
      expect(registro(execucao).dados).to include('versao' => versao)
      envio = Autonomia::Automacao::VersaoEnvio.sole
      expect(envio).to have_attributes(account_id: account.id, automacao_id: definicao.id, passo: 'p1', execucao_id: execucao.id,
                                       alvo_type: 'Conversation', alvo_id: conversa.id, contact_id: contato.id, versao: versao)
    end

    it 'com a vencedora escolhida, todo mundo recebe ela', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [com_versoes])
      linha(definicao).update!(vencedora: 2, escolhida_por: 'voce', escolhida_em: Time.current)
      comecar_e_rodar(definicao)

      expect(conversa.messages.outgoing.last.content).to eq('Olá! Tudo certo por aí?')
      expect(Autonomia::Automacao::VersaoEnvio.sole.versao).to eq(2)
    end

    it 'o envio que pulou não conta para o teste', :aggregate_failures do
      definicao = automacao_ligada(account, admin, [com_versoes(['Olá ', { '$valor' => 'contato.email' }])])
      linha(definicao).update!(vencedora: 2, escolhida_por: 'voce', escolhida_em: Time.current)
      contato.update!(email: nil)
      execucao = comecar_e_rodar(definicao)

      expect(registro(execucao).resultado).to eq('pulado')
      expect(registro(execucao).dados).not_to have_key('versao')
      expect(Autonomia::Automacao::VersaoEnvio.count).to eq(0)
    end
  end
end

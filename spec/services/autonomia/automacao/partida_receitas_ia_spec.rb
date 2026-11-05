require 'rails_helper'

# As receitas prontas Reclamação e Orçamento (#2523), como saem de automacao-receitas.yml, ligadas numa conta: começam na
# mensagem do cliente, e só na conversa que ainda não tem a etiqueta delas. Assim a IA não lê de novo a cada mensagem e
# a equipe é avisada uma vez.
RSpec.describe Autonomia::Automacao::Partida, :automacao_motor do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:conversa) { create(:conversation, account: account, status: :open) }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!('automacao_ia')
  end

  def ligada(chave)
    receita = Autonomia::Automacao::Catalogo.receitas.find { |item| item['chave'] == chave }.fetch('receita')
    create(:autonomia_automacao, account: account, ligada_por: admin).tap do |automacao|
      automacao.salvar_versao!(receita: receita, autor: admin)
      automacao.update!(ativa: true)
    end
  end

  def mensagem(message_type)
    create(:message, conversation: conversa, account: account, inbox: conversa.inbox, message_type: message_type)
  end

  # A Escuta pode já ter começado pela mesma mensagem: o que vale é a execução aberta para a conversa.
  def comecou?(definicao, disparo)
    described_class.new(definicao: definicao, alvo: conversa.reload, chave_gatilho: 'mensagem.criada', mensagem: disparo).call
    Autonomia::Automacao::Execucao.exists?(automacao_id: definicao.id, alvo: conversa)
  end

  { 'RECLAMACAO' => 'reclamacao', 'ORCAMENTO' => 'orcamento' }.each do |chave, etiqueta|
    describe chave do
      it 'começa na mensagem do cliente, na conversa sem a etiqueta' do
        expect(comecou?(ligada(chave), mensagem(:incoming))).to be(true)
      end

      it 'não começa na resposta da equipe' do
        expect(comecou?(ligada(chave), mensagem(:outgoing))).to be(false)
      end

      it "não começa na conversa que já tem a etiqueta #{etiqueta}" do
        conversa.update_labels([etiqueta])

        expect(comecou?(ligada(chave), mensagem(:incoming))).to be(false)
      end
    end
  end
end

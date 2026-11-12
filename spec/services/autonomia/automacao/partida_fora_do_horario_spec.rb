require 'rails_helper'

# A receita pronta Fora do horário (#2503), como sai de automacao-receitas.yml, ligada numa conta: só começa na mensagem
# do cliente que chega fora do horário de atendimento da caixa, no fuso da conta. Depois de responder, a execução fica
# aberta 12 horas, e as outras mensagens da mesma noite não começam de novo.
RSpec.describe Autonomia::Automacao::Partida, :automacao_motor do
  let(:account) { create(:account, locale: 'pt_BR', reporting_timezone: 'America/Sao_Paulo') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:receita) { Autonomia::Automacao::Catalogo.receitas.find { |item| item['chave'] == 'FORA_DO_HORARIO' }.fetch('receita') }
  let(:definicao) do
    create(:autonomia_automacao, account: account, ligada_por: admin).tap do |automacao|
      automacao.salvar_versao!(receita: receita, autor: admin)
      automacao.update!(ativa: true)
    end
  end
  let(:inbox) { create(:inbox, account: account, working_hours_enabled: true) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:fuso_da_conta) { Time.find_zone('America/Sao_Paulo') }

  before do
    ligar_motor(account)
    ligar_mensagens(account)
    account.enable_features!(Autonomia::HorarioUnicoCaixa::FEATURE)
  end

  def mensagem(message_type, **atributos)
    create(:message, conversation: conversa, account: account, inbox: inbox, message_type: message_type, **atributos)
  end

  def comecou?(disparo)
    described_class.new(definicao: definicao, alvo: disparo.conversation.reload, chave_gatilho: 'mensagem.criada', mensagem: disparo).call
    Autonomia::Automacao::Execucao.where(automacao_id: definicao.id, alvo: conversa).count
  end

  it 'não começa na mensagem do cliente dentro do horário (segunda, 10h no fuso da conta)' do
    travel_to(fuso_da_conta.local(2026, 11, 9, 10)) { expect(comecou?(mensagem(:incoming))).to eq(0) }
  end

  it 'começa na mensagem do cliente fora do horário (segunda, 21h no fuso da conta)' do
    travel_to(fuso_da_conta.local(2026, 11, 9, 21)) { expect(comecou?(mensagem(:incoming))).to eq(1) }
  end

  it 'a segunda mensagem da mesma noite não começa outra; a da equipe nunca começa', :aggregate_failures do
    travel_to(fuso_da_conta.local(2026, 11, 9, 21)) do
      expect(comecou?(mensagem(:incoming))).to eq(1)
      expect(comecou?(mensagem(:incoming))).to eq(1)
      expect(comecou?(mensagem(:outgoing))).to eq(1)
    end
  end

  it 'a caixa sem horário de atendimento ligado nunca está fora do horário' do
    inbox.update!(working_hours_enabled: false)

    travel_to(fuso_da_conta.local(2026, 11, 8, 3)) { expect(comecou?(mensagem(:incoming))).to eq(0) }
  end
end

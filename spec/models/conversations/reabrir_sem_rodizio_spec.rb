require 'rails_helper'

# #2216: reabrir sem o rodízio só vale para essa troca de status; o resto da atribuição automática segue igual.
RSpec.describe Conversations::ReabrirSemRodizio do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account, enable_auto_assignment: true) }
  let(:agent) { create(:user, account: account, role: :agent, auto_offline: false) }
  let(:conversa) { create(:conversation, account: account, inbox: inbox, status: :resolved, assignee: nil) }

  before { create(:inbox_member, user: agent, inbox: inbox) }

  it 'o open! de sempre ainda chama o rodízio' do
    conversa.open!

    expect(conversa.reload.assignee).to eq(agent)
  end

  it 'reabre sem chamar o rodízio' do
    conversa.reabrir_sem_rodizio!

    expect(conversa.reload).to be_open
    expect(conversa.assignee).to be_nil
  end

  it 'a próxima reabertura da mesma conversa volta a chamar o rodízio' do
    conversa.reabrir_sem_rodizio!
    conversa.resolved!
    conversa.open!

    expect(conversa.reload.assignee).to eq(agent)
  end

  describe '#reabrir_ao_escrever!' do
    before { inbox.update!(lock_to_single_conversation: true) }

    it 'trava a conversa antes de conferir a situação' do
      lida = Conversation.find(conversa.id)
      expect(lida).to receive(:lock!).with('FOR NO KEY UPDATE').ordered.and_call_original
      expect(lida).to receive(:open!).ordered.and_call_original

      ActiveRecord::Base.transaction { lida.reabrir_ao_escrever! }
      expect(lida.reload).to be_open
    end

    it 'conversa aberta não trava nada' do
      conversa.update!(status: :open)
      lida = Conversation.find(conversa.id)
      expect(lida).not_to receive(:lock!)

      ActiveRecord::Base.transaction { lida.reabrir_ao_escrever! }
      expect(lida.reload).to be_open
    end

    it 'dois envios ao mesmo tempo: o segundo, com a conversa velha na mão, não reabre de novo' do
      primeiro = Conversation.find(conversa.id)
      segundo = Conversation.find(conversa.id)

      primeiro.reabrir_ao_escrever!
      reaberta_em = primeiro.reload.status_changed_at

      expect(segundo).not_to receive(:open!)
      ActiveRecord::Base.transaction { segundo.reabrir_ao_escrever! }
      expect(segundo.reload.status_changed_at).to eq(reaberta_em)
    end
  end
end

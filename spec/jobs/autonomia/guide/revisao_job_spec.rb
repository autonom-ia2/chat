require 'rails_helper'

# O job da revisão de conversas (#3158, B8b): uma cadeia por revisão, e a espera pela vaga não vira cadeia nova.
RSpec.describe Autonomia::Guide::RevisaoJob do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :administrator) }
  let(:revisao) do
    Autonomia::Guide::Revisao.create!(account: account, user: user, status: 'rodando', titulo: 'Revisão', pedido: 'Por quê',
                                      selecao: {}, ids: [1], limite: 300, batimento_em: batimento)
  end
  let(:batimento) { Time.current }
  let(:trava) { "autonomia:guide:revisao:#{revisao.id}" }

  after { Redis::LockManager.new.unlock(trava) }

  describe 'com a trava ocupada' do
    before { Redis::LockManager.new.lock(trava, 60) }

    it 'sai quieto quando a outra cadeia está viva' do
      expect { described_class.perform_now(revisao.id) }.not_to have_enqueued_job(described_class)
    end

    context 'when a outra cadeia ficou sem batimento' do
      let(:batimento) { 10.minutes.ago }

      it 'tenta de novo mais tarde' do
        expect { described_class.perform_now(revisao.id) }.to have_enqueued_job(described_class).with(revisao.id)
      end
    end
  end

  context 'without vaga' do
    let(:batimento) { 10.minutes.ago }

    it 'espera na fila e renova o batimento, para o vigia não abrir outra cadeia', :aggregate_failures do
      allow(Autonomia::Guide::Revisoes::Semaforo).to receive(:entrar).and_return(false)

      expect { described_class.perform_now(revisao.id) }.to have_enqueued_job(described_class).with(revisao.id)
      expect(revisao.reload.batimento_em).to be > 1.minute.ago
    end
  end

  it 'não faz nada com a revisão que já terminou' do
    revisao.update!(status: 'concluida')

    expect { described_class.perform_now(revisao.id) }.not_to have_enqueued_job(described_class)
  end
end

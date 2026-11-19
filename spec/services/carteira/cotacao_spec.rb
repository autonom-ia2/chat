require 'rails_helper'

# E8 (#2901): o passo da história da cotação nesta vigência. Os valores chegam num hash ou soltos (no Ruby 3, soltos são
# keywords); as duas formas gravam o mesmo, sempre com a vigência. Tudo fictício.
RSpec.describe Carteira::Cotacao do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:marina) { create(:contact, account: account, name: 'Marina Exemplo', phone_number: '+5511900000023') }
  let(:seguro) { criar_apolice(marina, seguradora: 'Seguradora Exemplo', numero: 'EX-000001', fim_vigencia: 30.days.from_now.to_date) }
  let(:vigencia) { seguro.fim_vigencia.iso8601 }

  describe '.registrar' do
    it 'com os valores soltos (keywords)' do
      evento = described_class.registrar(seguro, 'proposta_nao_saiu', motivo: 'sem_preco', detalhe: 'x')

      expect(evento.reload.valores).to eq('vigencia' => vigencia, 'motivo' => 'sem_preco', 'detalhe' => 'x')
      expect(evento.user).to be_nil
    end

    it 'com os valores num hash, e quem fez' do
      evento = described_class.registrar(seguro, 'proposta_enviada', { mensagem: 42 }, user: admin)

      expect(evento.reload.valores).to eq('vigencia' => vigencia, 'mensagem' => 42)
      expect(evento.user).to eq(admin)
    end

    it 'sem valores, só a vigência' do
      evento = described_class.registrar(seguro, 'proposta_pedida')

      expect(evento.reload.valores).to eq('vigencia' => vigencia)
      expect(described_class.passo(seguro, 'proposta_pedida')).to eq(evento)
    end
  end
end

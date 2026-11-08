require 'rails_helper'

# #2067: o pedido "ficar com a conversa ao enviar" e a conferência do dono que a tela viu (Conversations::FicarAoEnviar).
RSpec.describe Conversations::FicarAoEnviar do
  let(:account) { create(:account) }
  let(:ana) { create(:user, account: account) }
  let(:joao) { create(:user, account: account) }
  let(:bot) { create(:agent_bot, account: account) }
  let(:conversation) { create(:conversation, account: account) }

  def params(**dados)
    ActionController::Parameters.new(dados)
  end

  describe '.pedido' do
    before { account.enable_features!('ficar_com_a_conversa_ao_enviar') }

    it 'lê o ícone e o dono visto, do JSON e do formulário', :aggregate_failures do
      json = described_class.pedido(account, params(ficar_com_a_conversa: true,
                                                    ficar_com_a_conversa_de: { tipo: 'pessoa', id: 9 }))
      expect(json).to have_attributes(fica: true, visto: { tipo: 'pessoa', id: 9 })

      form = described_class.pedido(account, params(ficar_com_a_conversa: 'false',
                                                    ficar_com_a_conversa_de: { tipo: 'ia', id: '' }))
      expect(form).to have_attributes(fica: false, visto: { tipo: 'ia', id: nil })
    end

    it 'sem o ícone no pedido: nil (a regra de antes)' do
      expect(described_class.pedido(account, params(content: 'oi'))).to be_nil
    end

    it 'dono visto ausente ou de tipo desconhecido: como se não tivesse dito', :aggregate_failures do
      expect(described_class.pedido(account, params(ficar_com_a_conversa: true)).visto).to be_nil
      expect(described_class.pedido(account, params(ficar_com_a_conversa: true,
                                                    ficar_com_a_conversa_de: { tipo: 'outro' })).visto).to be_nil
    end

    # Pega o 422 (TypeError/NoMethodError) com o dono visto malformado: a mensagem tem que sair.
    it 'dono visto malformado (texto, número, lista, id objeto): como se não tivesse dito, sem erro', :aggregate_failures do
      ['texto', 42, %w[pessoa 9], nil].each do |dado|
        pedido = described_class.pedido(account, params(ficar_com_a_conversa: true, ficar_com_a_conversa_de: dado))
        expect(pedido).to have_attributes(fica: true, visto: nil)
      end
      id_objeto = described_class.pedido(account, params(ficar_com_a_conversa: true,
                                                         ficar_com_a_conversa_de: { tipo: 'pessoa', id: { x: 1 } }))
      expect(id_objeto.visto).to eq(tipo: 'pessoa', id: 0)
      lista_no_tipo = described_class.pedido(account, params(ficar_com_a_conversa: true,
                                                             ficar_com_a_conversa_de: { tipo: ['ia'] }))
      expect(lista_no_tipo.visto).to be_nil
    end

    it 'o ícone é booleano estrito: só true/false e "true"/"false"/"1"/"0"', :aggregate_failures do
      { true => true, false => false, 'true' => true, 'false' => false, '1' => true, '0' => false }.each do |valor, fica|
        expect(described_class.pedido(account, params(ficar_com_a_conversa: valor)).fica).to be(fica)
      end
      ['sim', 'on', 'yes', 1, 0, '', %w[true], { a: 1 }].each do |valor|
        expect(described_class.pedido(account, params(ficar_com_a_conversa: valor))).to be_nil
      end
    end

    # Pega a flag desligada: o servidor ignora o pedido.
    it 'com a flag da conta desligada: nil' do
      account.disable_features!('ficar_com_a_conversa_ao_enviar')

      expect(described_class.pedido(account, params(ficar_com_a_conversa: true))).to be_nil
    end
  end

  describe '.mesmo_dono?' do
    def visto(tipo, id = nil)
      { tipo: tipo, id: id }
    end

    it 'sem ninguém e IA são a mesma situação', :aggregate_failures do
      expect(described_class.mesmo_dono?(visto('ninguem'), conversation)).to be(true)
      conversation.update!(ai_assignee: bot)
      expect(described_class.mesmo_dono?(visto('ninguem'), conversation)).to be(true)
      expect(described_class.mesmo_dono?(visto('ia'), conversation)).to be(true)
      expect(described_class.mesmo_dono?(nil, conversation)).to be(true)
    end

    it 'colega só se é o mesmo colega que a tela viu', :aggregate_failures do
      conversation.update!(assignee: joao)

      expect(described_class.mesmo_dono?(visto('pessoa', joao.id), conversation)).to be(true)
      expect(described_class.mesmo_dono?(visto('pessoa', ana.id), conversation)).to be(false)
      expect(described_class.mesmo_dono?(visto('ia'), conversation)).to be(false)
      expect(described_class.mesmo_dono?(visto('ninguem'), conversation)).to be(false)
      expect(described_class.mesmo_dono?(nil, conversation)).to be(false)
    end

    it 'a tela viu um colega e a conversa ficou sem ninguém: não' do
      expect(described_class.mesmo_dono?(visto('pessoa', joao.id), conversation)).to be(false)
    end
  end
end

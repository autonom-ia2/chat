require 'rails_helper'

# E6.6 (#2899) — "seu seguro em palavras simples": escrever (o modelo é um dublê; nenhuma chamada paga sai daqui),
# guardar o texto ajustado, por onde ele sai e mandar ao cliente só no clique. Tudo fictício.
RSpec.describe Carteira::Palavras do
  let(:account) { conta_com_carteira(locale: 'pt_BR') }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:pessoa) { create(:contact, account: account, name: 'Marina Exemplo de Souza', phone_number: '+5511900000041') }
  let(:seguro) do
    criar_apolice(pessoa, tipo: 'auto', seguradora: 'Seguradora Exemplo', numero: 'EX-000444', fim_vigencia: Date.new(2027, 5, 20),
                          inicio_vigencia: Date.new(2026, 5, 20), bem: 'Carro Exemplo 2021')
  end
  let(:cliente) { instance_double(Crm::Ai::ResponsesClient) }

  before { Carteira::Leitor::Liberado.ligar!(account) }

  def responde(texto)
    allow(cliente).to receive(:create).and_return({ text: { texto: texto }.to_json, usage: {} })
  end

  def conversa_com(pessoa_da_conversa = pessoa)
    create(:conversation, account: account, contact: pessoa_da_conversa)
  end

  def fora_da_janela!
    allow(Conversations::MessageWindowService).to receive(:new).and_return(instance_double(Conversations::MessageWindowService, can_reply?: false))
  end

  def recusa_de(&)
    yield
    nil
  rescue CustomExceptions::CarteiraRecusa => e
    e.message
  end

  describe Carteira::Palavras::Escrever do
    it 'guarda o texto com o "Oi" do primeiro nome, que a casa escreve: o nome nunca vai ao modelo' do
      responde('É o seguro do seu carro, da Seguradora Exemplo. Ele vale até 20/05/2027.')

      described_class.new(seguro, cliente: cliente).call

      expect(seguro.reload.palavras_texto).to eq("Oi, Marina!\nÉ o seguro do seu carro, da Seguradora Exemplo. Ele vale até 20/05/2027.")
      expect(cliente).to have_received(:create) do |**pedido|
        expect(JSON.parse(pedido[:input])).to eq('tipo' => 'auto', 'ramo' => nil, 'seguradora' => 'Seguradora Exemplo', 'comeca' => '2026-05-20',
                                                 'termina' => '2027-05-20', 'bem' => 'Carro Exemplo 2021', 'idioma' => 'pt_BR')
        expect(pedido[:input]).not_to include('Marina', '+5511900000041', 'EX-000444')
        expect(pedido[:schema]).to eq(described_class::SCHEMA)
      end
    end

    it 'a conta sem a chave não escreve nem chama ninguém' do
      Carteira::Leitor::Liberado.desligar!(account)
      responde('Texto')

      expect(recusa_de { described_class.new(seguro, cliente: cliente).call }).to eq('leitura_desligada')
      expect(cliente).not_to have_received(:create)
    end

    it 'o seguro de outra corretora e o cancelado não ganham palavras simples' do
      responde('Texto')
      de_fora = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', fim_vigencia: Date.new(2027, 6, 1), de_fora: true)
      cancelado = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', numero: 'EX-000555', cancelado_em: Time.current)

      [de_fora, cancelado].each do |apolice|
        expect(recusa_de { described_class.new(apolice, cliente: cliente).call }).to eq('pedido_invalido')
      end
      expect(cliente).not_to have_received(:create)
    end

    it 'falha da chamada, resposta cortada ou vazia: nao_deu_para_escrever, sem mexer no texto guardado' do
      seguro.update!(palavras_texto: 'Texto antigo')
      saidas = [{ text: { texto: '  ' }.to_json }, { text: { texto: 'Meio' }.to_json, incomplete_reason: 'max_output_tokens' },
                { text: 'não é json' }]

      saidas.each do |saida|
        allow(cliente).to receive(:create).and_return(saida)
        expect(recusa_de { described_class.new(seguro, cliente: cliente).call }).to eq('nao_deu_para_escrever')
      end
      allow(cliente).to receive(:create).and_raise(Crm::Ai::ResponsesClient::Error.new('falhou', status: 500))
      expect(recusa_de { described_class.new(seguro, cliente: cliente).call }).to eq('nao_deu_para_escrever')
      expect(seguro.reload.palavras_texto).to eq('Texto antigo')
    end

    it 'a conta sem a IA configurada não cria cliente' do
      allow(Crm::Ai::ResponsesClient).to receive(:new)

      expect(recusa_de { described_class.new(seguro).call }).to eq('nao_deu_para_escrever')
      expect(Crm::Ai::ResponsesClient).not_to have_received(:new)
    end
  end

  describe Carteira::Palavras::Salvar do
    it 'guarda o texto ajustado, sem os espaços das pontas' do
      described_class.new(seguro).call("  Oi, Marina!\nTexto ajustado.  ")

      expect(seguro.reload.palavras_texto).to eq("Oi, Marina!\nTexto ajustado.")
    end

    it 'recusa o vazio, o comprido demais e o seguro de outra corretora' do
      expect(recusa_de { described_class.new(seguro).call('   ') }).to eq('falta_texto')
      expect(recusa_de { described_class.new(seguro).call('a' * (Carteira::Palavras::TEXTO_MAXIMO + 1)) }).to eq('texto_longo')
      expect(recusa_de { described_class.new(seguro).call(nil) }).to eq('pedido_invalido')
      de_fora = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', fim_vigencia: Date.new(2027, 6, 1), de_fora: true)
      expect(recusa_de { described_class.new(de_fora).call('Texto') }).to eq('pedido_invalido')
      expect(seguro.reload.palavras_texto).to be_nil
    end
  end

  describe Carteira::Palavras::Conversa do
    it 'sem conversa com o contato: sem_conversa' do
      expect(described_class.new(seguro, user: admin).envio).to eq('sem_conversa')
    end

    it 'com conversa que aceita mensagem: conversa; fora do prazo do canal: fora_da_janela' do
      conversa = conversa_com

      expect(described_class.new(seguro, user: admin).conversa).to eq(conversa)
      expect(described_class.new(seguro, user: admin).envio).to eq('conversa')

      fora_da_janela!
      expect(described_class.new(seguro, user: admin).envio).to eq('fora_da_janela')
    end

    it 'a conversa de outra pessoa não serve' do
      conversa_com(create(:contact, account: account, name: 'Outra Exemplo'))

      expect(described_class.new(seguro, user: admin).envio).to eq('sem_conversa')
    end

    it 'a tela recebe o texto, quando saiu, a frase do fim e por onde sai' do
      seguro.update!(palavras_texto: 'Texto', palavras_enviadas_em: Time.zone.at(1_800_000_000))

      esperado = { texto: 'Texto', enviadoEm: 1_800_000_000, vale: 'Vale o que está escrito na sua apólice.', envio: 'sem_conversa' }

      expect(described_class.new(seguro, user: admin).para_a_tela).to eq(esperado)
    end
  end

  describe Carteira::Palavras::Enviar do
    it 'manda o texto guardado com a frase do fim, como mensagem de saída da pessoa, e marca o envio' do
      conversa = conversa_com
      seguro.update!(palavras_texto: "Oi, Marina!\nTexto conferido.")

      expect { described_class.new(seguro, user: admin).call }.to change(conversa.messages.outgoing, :count).by(1)

      mensagem = conversa.messages.outgoing.last
      expect(mensagem).to have_attributes(content: "Oi, Marina!\nTexto conferido.\n\nVale o que está escrito na sua apólice.", sender: admin,
                                          private: false)
      expect(seguro.reload.palavras_enviadas_em).to be_present
      expect(seguro.eventos.sole).to have_attributes(tipo: 'palavras_enviadas', user_id: admin.id, valores: { 'mensagem' => mensagem.id })
    end

    it 'nada sai sem texto, sem conversa, fora do prazo do canal ou no seguro de outra corretora' do
      conversa = conversa_com
      expect(recusa_de { described_class.new(seguro, user: admin).call }).to eq('falta_texto')

      seguro.update!(palavras_texto: 'Texto')
      fora_da_janela!
      expect(recusa_de { described_class.new(seguro, user: admin).call }).to eq('fora_da_janela')

      conversa.destroy!
      expect(recusa_de { described_class.new(seguro, user: admin).call }).to eq('sem_conversa')

      de_fora = criar_apolice(pessoa, seguradora: 'Seguradora Exemplo', fim_vigencia: Date.new(2027, 6, 1), de_fora: true,
                                      palavras_texto: 'Texto')
      expect(recusa_de { described_class.new(de_fora, user: admin).call }).to eq('pedido_invalido')

      expect(Message.where(message_type: :outgoing).count).to eq(0)
      expect(seguro.reload.palavras_enviadas_em).to be_nil
    end

    it 'a conta sem a chave não manda' do
      conversa_com
      seguro.update!(palavras_texto: 'Texto')
      Carteira::Leitor::Liberado.desligar!(account)

      expect(recusa_de { described_class.new(seguro, user: admin).call }).to eq('leitura_desligada')
      expect(Message.where(message_type: :outgoing).count).to eq(0)
    end
  end
end

require 'rails_helper'

# A rajada do cliente (#3211, P1): o que ele escreveu desde a última FALA do agente, contando a fala e não o pedaço.
RSpec.describe Autonomia::Agents::Operate::RajadaDoCliente do
  def recebida(texto) = instance_double(Message, incoming?: true, content: texto, content_attributes: {})
  def pedaco(indice) = instance_double(Message, incoming?: false, content_attributes: { 'autonomia_chunk_index' => indice })
  def fala_de_gente = instance_double(Message, incoming?: false, content_attributes: {})

  describe '.mensagens' do
    # Pega: a pergunta ser só a última mensagem, ou voltar além da última fala e repetir o que já foi respondido.
    it 'tudo desde a última fala' do
      m1 = recebida('quero cotar')
      m2 = recebida('pra Portugal')

      expect(described_class.mensagens([recebida('antiga'), fala_de_gente, m1, m2])).to eq([m1, m2])
    end

    # Review Focus 3. Pega: a rajada vazia (a última saída é um pedaço posterior) ou a mensagem já respondida junto.
    it 'pedaços intercalados não fecham a rajada' do
      m2 = recebida('e pra 2 pessoas?')

      expect(described_class.mensagens([recebida('oi'), pedaco(0), m2, pedaco(1), pedaco(2)])).to eq([m2])
    end

    # Pega: a continuação da cadeia no meio da rajada cortar o que veio antes dela.
    it 'a mensagem antes de uma continuação entra, a anterior ao 1º pedaço não' do
      m2 = recebida('e pra 2 pessoas?')
      m3 = recebida('saindo dia 02')

      expect(described_class.mensagens([recebida('oi'), pedaco(0), m2, pedaco(1), m3])).to eq([m2, m3])
    end

    # Pega: o 1º pedaço (índice 0) ser tratado como continuação e a rajada engolir a pergunta já respondida.
    it 'o 1º pedaço fecha a rajada' do
      expect(described_class.mensagens([recebida('oi'), pedaco(0)])).to eq([])
    end

    it 'sem nenhuma fala, todas as recebidas' do
      expect(described_class.mensagens([recebida('a'), recebida('b')]).size).to eq(2)
    end

    it 'content_attributes ausente não quebra' do
      sem_atributos = instance_double(Message, incoming?: false, content_attributes: nil)

      expect(described_class.mensagens([recebida('a'), sem_atributos, recebida('b')]).size).to eq(1)
    end
  end

  describe '.texto' do
    # Pega: mensagem vazia virando linha em branco, ou o cliente que repete a mesma frase ser perguntado duas vezes seguidas.
    it 'junta com quebra de linha, sem vazias nem repetidas seguidas' do
      msgs = [recebida('oi'), recebida('oi'), recebida('  '), recebida('tudo bem?'), recebida('oi')]

      expect(described_class.texto(msgs, &:content)).to eq("oi\ntudo bem?\noi")
    end

    it 'sem mensagens, texto vazio' do
      expect(described_class.texto([], &:content)).to eq('')
    end
  end
end

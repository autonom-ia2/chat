require 'rails_helper'

RSpec.describe Autonomia::Automacao::Valores do
  let(:account) { create(:account) }
  let(:contato) { create(:contact, account: account, name: 'Maria', custom_attributes: { 'apolice.numero' => '991' }) }
  let(:conversa) { create(:conversation, account: account, contact: contato, custom_attributes: { 'origem' => 'anuncio' }) }
  let(:valores) { described_class.new(conversa: conversa) }

  it 'lê campos da conversa e do contato' do
    expect(valores.ler('conversa.id')).to eq(conversa.display_id)
    expect(valores.ler('conversa.caixa_id')).to eq(conversa.inbox_id)
    expect(valores.ler('contato.nome')).to eq('Maria')
  end

  it 'lê atributo personalizado pela chave, mesmo com ponto' do
    expect(valores.ler('conversa.atributos.origem')).to eq('anuncio')
    expect(valores.ler('contato.atributos.apolice.numero')).to eq('991')
    expect(valores.ler('contato.atributos.ausente')).to be_nil
  end

  it 'só aceita caminho da lista' do
    expect(described_class.caminho_valido?('contato.atributos.placa')).to be(true)
    expect(described_class.caminho_valido?('contato.atributos.')).to be(false)
    expect(described_class.caminho_valido?('contato.senha')).to be(false)
    expect { valores.ler('contato.senha') }.to raise_error(ArgumentError)
  end
end

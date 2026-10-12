require 'rails_helper'

# Chaves do catálogo dentro de um texto, na sintaxe `{{chave}}` (#1354): leitura por index, sem regex.
RSpec.describe Ai::Redacao::Chaves do
  it 'extrai as chaves na ordem, com repetição e sem espaços em volta' do
    texto = 'Oi, {{cliente.primeiro_nome}}! Dia {{ horario.data_hora }}: {{horario.link_gestao}} e {{cliente.primeiro_nome}}.'

    expect(described_class.extrair(texto)).to eq(%w[cliente.primeiro_nome horario.data_hora horario.link_gestao cliente.primeiro_nome])
  end

  it 'quebra o texto em partes de texto fixo e de chave' do
    partes = described_class.partes('Oi, {{cliente.primeiro_nome}}!')

    expect(partes.map { |parte| [parte.tipo, parte.valor] }).to eq([[:texto, 'Oi, '], [:chave, 'cliente.primeiro_nome'], [:texto, '!']])
  end

  it 'texto sem chave é uma parte só' do
    expect(described_class.extrair('Sem campo nenhum.')).to eq([])
    expect(described_class).not_to be_malformado('Sem campo nenhum.')
  end

  it 'acusa chave sem fechar, chave vazia, chave com chave dentro e }} sobrando' do
    ['Oi {{cliente.primeiro_nome', 'Oi {{}} tchau', 'Oi {{a{{b}} tchau', 'Oi }} tchau'].each do |texto|
      expect(described_class).to be_malformado(texto), texto
    end
  end

  it 'preenche cada chave pelo bloco, sem mexer no texto fixo' do
    texto = described_class.preencher('Oi, {{cliente.primeiro_nome}}! {{horario.data_hora}}', &:upcase)

    expect(texto).to eq('Oi, CLIENTE.PRIMEIRO_NOME! HORARIO.DATA_HORA')
  end
end

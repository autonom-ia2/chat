require 'rails_helper'

# Agente pronto Seguro Viagem Universal (#3211): as duas tabelas novas.
RSpec.describe 'Tabelas do agente Seguro Viagem Universal', type: :model do
  let(:conexao) { ActiveRecord::Base.connection }

  it 'acesso: um por agente, credenciais em text' do
    cols = conexao.columns('autonomia_acessos_da_seguradora').index_by(&:name)
    expect(cols.keys).to include('account_id', 'autonomia_agent_id', 'seguradora', 'login', 'senha', 'login_dica',
                                 'estado', 'conferido_em', 'motivo', 'capacidades')
    expect(cols['login'].type).to eq(:text)
    expect(cols['senha'].type).to eq(:text)
    indice = conexao.indexes('autonomia_acessos_da_seguradora').find { |i| i.columns == ['autonomia_agent_id'] }
    expect(indice.unique).to be(true)
  end

  it 'cotação: jsonb para pedido, planos e proposta' do
    cols = conexao.columns('autonomia_cotacoes_de_viagem').index_by(&:name)
    expect(cols.slice('pedido', 'planos', 'proposta').values.map(&:sql_type)).to all(eq('jsonb'))
    expect(cols['conversation_id'].null).to be(false)
  end

  it 'toda chave para tabela apagada pela exclusão da conta tem índice (R2)' do
    { 'autonomia_acessos_da_seguradora' => [['account_id'], ['autonomia_agent_id']],
      'autonomia_cotacoes_de_viagem' => [['account_id'], ['autonomia_agent_id'], %w[conversation_id id]] }.each do |tabela, esperados|
      colunas = conexao.indexes(tabela).map(&:columns)
      expect(colunas).to include(*esperados)
    end
  end
end

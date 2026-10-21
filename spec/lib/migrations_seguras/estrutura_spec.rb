require 'rails_helper'

RSpec.describe MigrationsSeguras::Estrutura do
  describe '.diferencas' do
    it 'aponta o caminho de cada diferença e ignora a ordem das chaves' do
      antes = { 'tabelas' => { 'contacts' => { 'colunas' => { 'email' => { 'nulo' => true }, 'nome' => {} } } } }
      depois = { 'tabelas' => { 'contacts' => { 'colunas' => { 'nome' => {}, 'email' => { 'nulo' => false } } } } }

      expect(described_class.diferencas(antes, antes.deep_dup)).to be_empty
      expect(described_class.diferencas(antes, depois)).to eq(['tabelas.contacts.colunas.email.nulo'])
    end

    it 'aponta o que só existe de um lado' do
      expect(described_class.diferencas({ 'a' => 1 }, { 'b' => 1 })).to eq(%w[a b])
    end
  end

  describe '.capturar' do
    it 'lê tabelas, colunas, índices, chaves e gatilhos do banco, sem as tabelas do Rails' do
      retrato = described_class.capturar

      contatos = retrato.dig('tabelas', 'contacts')
      expect(contatos.dig('colunas', 'account_id')).to include('tipo' => 'integer', 'nulo' => false)
      expect(contatos['indices']).to be_present
      expect(retrato['tabelas']).not_to include('schema_migrations', 'ar_internal_metadata')
      expect(retrato['extensoes']).to include('pg_trgm')
      expect(retrato['gatilhos']).to include('email_reputation_audits.email_reputation_audit_append_only')
    end
  end
end

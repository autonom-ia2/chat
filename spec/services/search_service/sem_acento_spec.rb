require 'rails_helper'

# #2211 — a busca só usa o índice se a expressão da consulta for igual à do índice. A tabela de letras mora na constante
# e, por extenso, no db/schema.rb; este spec falha quando as duas se separam.
RSpec.describe SearchService::SemAcento do
  let(:schema) { Rails.root.join('db/schema.rb').read }
  let(:tabela) { "'#{described_class::COM_ACENTO}'::text, '#{described_class::SEM_ACENTO}'::text" }

  {
    'idx_contacts_nome_sem_acento_trgm' => '(name)::text',
    'idx_messages_conteudo_sem_acento_trgm' => 'content',
    'idx_attachments_transcricao_sem_acento_trgm' => "(meta ->> 'transcribed_text'::text)"
  }.each do |indice, coluna|
    it "o índice #{indice} do schema.rb tem a expressão da constante" do
      linha = schema.lines.find { |texto| texto.include?("name: \"#{indice}\"") }
      expect(linha).to include("t.index \"lower(translate(#{coluna}, #{tabela})) gin_trgm_ops\"", 'using: :gin')
    end

    it "o índice #{indice} existe no banco de teste com a mesma tabela" do
      definicao = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(['SELECT pg_get_indexdef(indexrelid) FROM pg_index JOIN pg_class ON ' \
                                               'pg_class.oid = indexrelid WHERE relname = ? AND indisvalid', indice])
      )
      expect(definicao).to include("lower(translate(#{coluna}, #{tabela})) gin_trgm_ops")
    end
  end

  it 'as duas metades da tabela têm o mesmo tamanho e cada letra aparece uma vez' do
    expect(described_class::COM_ACENTO.length).to eq(described_class::SEM_ACENTO.length)
    expect(described_class::COM_ACENTO.chars.uniq.length).to eq(described_class::COM_ACENTO.length)
  end

  it 'cada letra vira a letra de base da sua forma decomposta (NFD)' do
    pares = described_class::COM_ACENTO.chars.zip(described_class::SEM_ACENTO.chars)
    expect(pares.reject { |com, sem| com.unicode_normalize(:nfd)[0] == sem }).to be_empty
  end

  it 'o Ruby e o banco tiram o acento do mesmo jeito' do
    texto = "João da Conceição Ü #{described_class::COM_ACENTO}"
    no_banco = ActiveRecord::Base.connection.select_value("SELECT #{described_class.sql(ActiveRecord::Base.connection.quote(texto))}")
    expect(no_banco).to eq(described_class.texto(texto))
  end

  it 'tira acento e põe em minúscula' do
    expect(described_class.texto('João CONCEIÇÃO Ávila')).to eq('joao conceicao avila')
  end
end

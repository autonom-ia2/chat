require 'rails_helper'

# #2211 — a busca só usa o índice se a expressão da consulta for igual à do índice. A lista de acentos mora na constante
# e, por extenso, no db/schema.rb e no banco; este spec falha quando eles se separam.
RSpec.describe SearchService::SemAcento do
  let(:schema) { Rails.root.join('db/schema.rb').read }
  let(:expressao_no_schema) do
    ->(coluna) { "lower(translate(NORMALIZE(#{coluna}, NFD), '#{described_class::ACENTOS_COMBINANTES}'::text, ''::text)) gin_trgm_ops" }
  end

  {
    'idx_contacts_nome_sem_acento_trgm' => 'name',
    'idx_crm_cards_titulo_sem_acento_trgm' => 'title',
    'idx_messages_conteudo_sem_acento_trgm' => 'content',
    'idx_attachments_transcricao_sem_acento_trgm' => "(meta ->> 'transcribed_text'::text)"
  }.each do |indice, coluna|
    it "o índice #{indice} do schema.rb tem a expressão da constante" do
      linha = schema.lines.find { |texto| texto.include?("name: \"#{indice}\"") }
      expect(linha).to include("t.index \"#{expressao_no_schema.call(coluna)}\"", 'using: :gin')
    end

    it "o índice #{indice} existe e é válido no banco de teste, com a mesma lista" do
      definicao = ActiveRecord::Base.connection.select_value(
        ActiveRecord::Base.sanitize_sql_array(['SELECT pg_get_indexdef(indexrelid) FROM pg_index JOIN pg_class ON ' \
                                               'pg_class.oid = indexrelid WHERE relname = ? AND indisvalid', indice])
      )
      expect(definicao).to include(expressao_no_schema.call(coluna))
    end
  end

  it 'a lista é exatamente a dos acentos que a NFD gera para as letras de U+00C0 a U+017F' do
    gerados = (0xC0..0x17F).flat_map { |codigo| [codigo].pack('U').unicode_normalize(:nfd).chars.drop(1) }.uniq.sort
    expect(described_class::ACENTOS_COMBINANTES.chars.sort).to eq(gerados)
  end

  it 'toda letra de U+00C0 a U+017F que se decompõe vira a letra ASCII de base' do
    letras = (0xC0..0x17F).map { |codigo| [codigo].pack('U') }.select { |letra| letra.unicode_normalize(:nfd).length > 1 }
    expect(letras.map { |letra| described_class.texto(letra) }).to all(satisfy { |base| ('a'..'z').cover?(base) })
  end

  it 'o Ruby e o banco tiram o acento do mesmo jeito' do
    letras = (0xC0..0x17F).map { |codigo| [codigo].pack('U') }.select { |letra| letra.unicode_normalize(:nfd).length > 1 }
    texto = "João da Conceição Ávila #{letras.join}"
    no_banco = ActiveRecord::Base.connection.select_value("SELECT #{described_class.sql(ActiveRecord::Base.connection.quote(texto))}")
    expect(no_banco).to eq(described_class.texto(texto))
  end

  it 'tira acento e põe em minúscula' do
    expect(described_class.texto('João CONCEIÇÃO Ávila')).to eq('joao conceicao avila')
  end
end

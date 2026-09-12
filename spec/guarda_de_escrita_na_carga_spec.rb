require 'rails_helper'

# AUTOTESTE DA GUARDA (regra 3, como em `recusa_guarda_spec`): um subscriber quebrado devolveria
# lista vazia e a guarda passaria elogiando o silêncio. Aqui ela reprova.
RSpec.describe GuardaDeEscritaNaCarga do
  # A lista é acumulador de módulo e já foi lida pelo `before(:suite)`; ainda assim, devolvemos o
  # processo como estava.
  around do |exemplo|
    anterior = described_class.escritas.dup
    described_class.escritas.clear
    exemplo.run
    described_class.escritas.replace(anterior)
  end

  describe '.registrar' do
    it 'anota INSERT, UPDATE e DELETE com o arquivo e a linha de quem escreveu' do
      described_class.registrar(sql: 'INSERT INTO active_storage_blobs (key) VALUES ($1)')
      described_class.registrar(sql: 'UPDATE accounts SET name = $1')
      described_class.registrar(sql: 'DELETE FROM accounts WHERE id = $1')

      expect(described_class.escritas.size).to eq(3)
      expect(described_class.escritas.first).to include('spec/guarda_de_escrita_na_carga_spec.rb:',
                                                        'INSERT INTO active_storage_blobs')
    end

    it 'ignora leitura e transacao, que a carga faz sem sujar nada' do
      ['SELECT COUNT(*) FROM accounts', 'BEGIN', 'COMMIT', 'SHOW search_path'].each do |sql|
        described_class.registrar(sql: sql)
      end

      expect(described_class.escritas).to be_empty
    end
  end

  describe '.conferir!' do
    it 'nao reprova quando a carga nao escreveu' do
      expect { described_class.conferir! }.not_to raise_error
    end

    it 'reprova com o endereco e o SQL quando a carga escreveu' do
      described_class.registrar(sql: 'INSERT INTO active_storage_blobs (key) VALUES ($1)')

      expect { described_class.conferir! }
        .to raise_error(/durante a CARGA.*guarda_de_escrita_na_carga_spec\.rb:.*INSERT INTO active_storage_blobs/m)
    end
  end
end

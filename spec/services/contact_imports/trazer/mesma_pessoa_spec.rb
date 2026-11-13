require 'rails_helper'

# #2896 — "Trazer minha lista": a mesma pessoa em várias linhas. Mesmo telefone (com ou sem o nono dígito) ou mesmo
# e-mail (sem diferença de maiúscula) sem dado em conflito vira UMA linha completada; com conflito, a segunda vira
# problema de linha repetida. Nunca por nome igual. As linhas são as do validador (aqui, só os campos que contam).
RSpec.describe ContactImports::Trazer::MesmaPessoa, :aggregate_failures do
  # dados: nome:, telefone:, email:, empresa:, extras: e erros:, só os que a linha tem.
  def linha(numero, **dados)
    nome, telefone, email, empresa = dados.values_at(:nome, :telefone, :email, :empresa)
    extras = dados.fetch(:extras, {})
    erros = dados.fetch(:erros, [])
    { row_number: numero, raw_name: nome.to_s, normalized_name: nome.to_s, normalized_phone: telefone,
      normalized_phone_hash: telefone && "hash-#{telefone}", raw_phone_masked: telefone && "mascara-#{telefone}", ninth_digit_added: false,
      email: email, email_hash: email && "hash-#{email}", email_masked: email && "mascara-#{email}", company_name: empresa,
      extra_values: extras, errors: erros }
  end

  def resolver(linhas)
    [described_class.new(linhas).call, linhas]
  end

  it 'junta as linhas com o mesmo telefone e completa a primeira com o que só a outra tinha' do
    juntadas, linhas = resolver([
                                  linha(2, nome: 'Ana Albuquerino', telefone: '+5511987650001', extras: { 'Plano' => 'Ouro' }),
                                  linha(3, nome: 'ANA  ALBUQUERINO', telefone: '+5511987650001', email: 'ana@exemplo.com.br', empresa: 'Padaria',
                                           extras: { 'Plano' => 'Prata', 'Cidade' => 'Campinas' })
                                ])

    expect(juntadas).to eq(1)
    expect(linhas.sole).to include(row_number: 2, normalized_name: 'Ana Albuquerino', normalized_phone: '+5511987650001',
                                   email: 'ana@exemplo.com.br', email_hash: 'hash-ana@exemplo.com.br', email_masked: 'mascara-ana@exemplo.com.br',
                                   company_name: 'Padaria', extra_values: { 'Plano' => 'Ouro', 'Cidade' => 'Campinas' }, errors: [])
  end

  it 'trata como o mesmo telefone o número com e sem o nono dígito' do
    juntadas, linhas = resolver([linha(2, nome: 'Ana', telefone: '+5511987650001'), linha(3, telefone: '+551187650001', email: 'ana@exemplo.com.br')])

    expect(juntadas).to eq(1)
    expect(linhas.sole).to include(row_number: 2, normalized_phone: '+5511987650001', email: 'ana@exemplo.com.br')
  end

  it 'junta pelo mesmo e-mail sem diferença de maiúscula, e a primeira ganha o nome e o telefone que não tinha' do
    juntadas, linhas = resolver([linha(2, email: 'Ana@Exemplo.com.br'),
                                 linha(3, nome: 'Ana', telefone: '+5511987650001', email: 'ana@exemplo.com.br')])

    expect(juntadas).to eq(1)
    expect(linhas.sole).to include(row_number: 2, raw_name: 'Ana', normalized_name: 'Ana', normalized_phone: '+5511987650001',
                                   normalized_phone_hash: 'hash-+5511987650001', email: 'Ana@Exemplo.com.br')
  end

  it 'nunca junta por nome igual' do
    juntadas, linhas = resolver([linha(2, nome: 'Ana Albuquerino', telefone: '+5511987650001'),
                                 linha(3, nome: 'Ana Albuquerino', telefone: '+5511987650002'),
                                 linha(4, nome: 'Ana Albuquerino', email: 'ana@exemplo.com.br')])

    expect(juntadas).to eq(0)
    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, []], [4, []]])
  end

  it 'com dado em conflito, a segunda linha vira problema e guarda a primeira' do
    casos = {
      'nome' => [linha(2, nome: 'Ana', telefone: '+5511987650001'), linha(3, nome: 'Bia', telefone: '+5511987650001')],
      'e-mail' => [linha(2, telefone: '+5511987650001', email: 'a@exemplo.com.br'), linha(3, telefone: '+5511987650001', email: 'b@exemplo.com.br')],
      'empresa' => [linha(2, telefone: '+5511987650001', empresa: 'Padaria'), linha(3, telefone: '+5511987650001', empresa: 'Mercado')]
    }
    casos.each do |caso, linhas|
      juntadas, resolvidas = resolver(linhas)

      expect(juntadas).to eq(0), caso
      expect(resolvidas.pluck(:row_number, :errors)).to eq([[2, []], [3, ['duplicate_phone_in_file']]]), caso
      expect(resolvidas.last[:outra]).to equal(resolvidas.first), caso
    end
  end

  it 'pelo mesmo e-mail com telefones diferentes, o problema é do e-mail' do
    _juntadas, linhas = resolver([linha(2, telefone: '+5511987650001', email: 'ana@exemplo.com.br'),
                                  linha(3, telefone: '+5511987650002', email: 'ANA@exemplo.com.br')])

    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, ['duplicate_email_in_file']]])
  end

  it 'nome com outra caixa, acento ou espaço não é conflito' do
    juntadas, = resolver([linha(2, nome: 'João  da Silva', telefone: '+5511987650001'), linha(3, nome: 'joao da silva', telefone: '+5511987650001')])

    expect(juntadas).to eq(1)
  end

  it 'junta três linhas da mesma pessoa, ligadas por telefone e por e-mail' do
    juntadas, linhas = resolver([linha(2, nome: 'Ana', telefone: '+5511987650001'), linha(3, telefone: '+5511987650001', email: 'ana@exemplo.com.br'),
                                 linha(4, email: 'ana@exemplo.com.br', empresa: 'Padaria')])

    expect(juntadas).to eq(2)
    expect(linhas.sole).to include(row_number: 2, email: 'ana@exemplo.com.br', company_name: 'Padaria')
  end

  it 'não olha a linha que já tem erro' do
    juntadas, linhas = resolver([linha(2, nome: 'Ana', telefone: '+5511987650001'),
                                 linha(3, nome: 'Ana', telefone: '+5511987650001', erros: ['formula_detected'])])

    expect(juntadas).to eq(0)
    expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, ['formula_detected']]])
  end

  # E4 (#2897): na planilha que traz seguros cada linha é um seguro da pessoa.
  describe 'sem juntar (a planilha que traz seguros)' do
    def resolver_sem_juntar(linhas)
      [described_class.new(linhas, juntar: false).call, linhas]
    end

    it 'as três linhas da mesma pessoa ficam na lista, como vieram, e nenhuma é contada como juntada' do
      juntadas, linhas = resolver_sem_juntar([
                                               linha(2, nome: 'Ana Albuquerino', telefone: '+5511987650001', extras: { 'Apólice' => 'EX-001234' }),
                                               linha(3, nome: 'Ana Albuquerino', telefone: '+5511987650001', email: 'ana@exemplo.com.br',
                                                        extras: { 'Apólice' => 'EX-005678' }),
                                               linha(4, nome: 'Ana Albuquerino', email: 'ANA@exemplo.com.br', extras: { 'Apólice' => 'VD-000042' })
                                             ])

      expect(juntadas).to eq(0)
      expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, []], [4, []]])
      expect(linhas.pluck(:email)).to eq([nil, 'ana@exemplo.com.br', 'ANA@exemplo.com.br'])
      expect(linhas.pluck(:extra_values)).to eq([{ 'Apólice' => 'EX-001234' }, { 'Apólice' => 'EX-005678' }, { 'Apólice' => 'VD-000042' }])
    end

    it 'o dado em conflito continua virando problema na segunda linha' do
      juntadas, linhas = resolver_sem_juntar([linha(2, nome: 'Ana Albuquerino', telefone: '+5511987650001'),
                                              linha(3, nome: 'Bruno Brandolim', telefone: '+5511987650001')])

      expect(juntadas).to eq(0)
      expect(linhas.pluck(:row_number, :errors)).to eq([[2, []], [3, ['duplicate_phone_in_file']]])
      expect(linhas.last[:outra]).to equal(linhas.first)
    end
  end
end

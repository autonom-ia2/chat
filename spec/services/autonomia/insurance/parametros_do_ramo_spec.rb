require 'rails_helper'

# O FORMULÁRIO DE UM RAMO QUE NÃO É AUTO NASCE DO ADAPTER (chat#591, fase 2 da receita de ramo).
#
# O schema daqui é o de residencial GERADO pela CLI do adapter (`Mock::SCHEMA_RESIDENCIAL`, commit
# anotado no mock), não escrito à mão. O que se prova:
#   só a origem `cliente` vira pergunta — `derivado` e `escolha` não entram (critério 3 da issue);
#   campo de cliente sem descrição QUEBRA o formulário, não some dele (critério 2);
#   `valores` viram `enum` e `descricao` vira a descrição, sem crase e sem travessão.
#
# PROVA POR MUTAÇÃO: ver o relatório da PR (tirar o filtro de origem em `expostos`; tirar o `nil` do
# `enum` anulável em `Native::Base#propriedade`).
RSpec.describe Autonomia::Insurance::Parametros do
  let(:schema) { Autonomia::Insurance::Connector::Mock::SCHEMA_RESIDENCIAL }
  let(:grupos) { described_class.do_ramo(schema) }
  let(:folhas) { grupos.flat_map { |g| g['properties'].map { |p| ["#{g['name']}.#{p['name']}", p] } }.to_h }
  let(:do_cliente) { schema['campos'].select { |c| c['origem'] == 'cliente' } }

  def com_campo(campo)
    schema.merge('campos' => schema['campos'] + [campo])
  end

  it 'declara exatamente os campos de origem cliente do adapter, e nenhum derivado ou escolha' do
    fora = schema['campos'].reject { |c| c['origem'] == 'cliente' }.map { |c| c['campo'] }

    expect(folhas.keys).to match_array(do_cliente.map { |c| c['campo'] })
    expect(folhas.size).to eq(18)
    # O valor a segurar é pergunta ao cliente desde adapters#80.
    expect(folhas).to have_key('configuracoes.isDanosIncendioRaioExplosao')
    expect(fora).to include('configuracoes.imovelLogradouro', 'configuracoes.areaRisco')
    expect(folhas.keys & fora).to be_empty
  end

  it 'a descrição de cada campo é a do adapter, sem crase e sem travessão' do
    do_cliente.each do |campo|
      descricao = folhas.fetch(campo['campo'])['description']

      expect(descricao).to eq(campo['descricao'])
      expect(descricao).not_to include('`', '—', '–')
    end
  end

  it 'valores viram enum no tipo do campo, e todo campo é anulável' do
    uso = folhas.fetch('configuracoes.imovelUso')

    expect(uso['type']).to eq('number')
    expect(uso['enum']).to eq([1, 2, 3])
    expect(folhas.values.count { |p| p.key?('enum') }).to eq(schema['campos'].count { |c| c['valores'].present? })
    expect(folhas.values).to all(include('required' => false))
    expect(folhas.fetch('segurado.nome')).not_to have_key('enum')
  end

  # Código com zero à esquerda ("08") é o número 8, e não 8.0: `Integer` sem base lê "08" como octal inválido e o
  # código ia ao adapter como decimal (revisão da #592).
  it 'código numérico com zero à esquerda vira o inteiro' do
    uso = described_class.new({}).send(:numeros, %w[01 08 10])

    expect(uso).to eq([1, 8, 10])
  end

  it 'os grupos são os do adapter, com o rótulo genérico: nenhum nome de grupo digitado aqui' do
    expect(grupos.map { |g| g['name'] }).to eq(%w[segurado configuracoes])
    expect(grupos.map { |g| g['description'] }).to eq(['Campos de segurado.', 'Campos de configuracoes.'])
    expect(described_class.new(schema, ramo: true).nomes_dos_grupos).to eq(%w[segurado configuracoes])
  end

  describe 'campo novo do adapter que não dá para oferecer quebra, não some' do
    # A mensagem da recusa, conferida por inclusão de texto.
    def recusa(schema_com_defeito)
      described_class.do_ramo(schema_com_defeito)
      nil
    rescue described_class::FormularioInvalido => e
      e.message
    end

    it 'campo de cliente sem descrição recusa o formulário inteiro, dizendo qual' do
      sem = com_campo('campo' => 'configuracoes.novo', 'tipo' => 'texto', 'origem' => 'cliente')

      expect(recusa(sem)).to include('configuracoes.novo sem descricao')
    end

    it 'descrição com crase ou travessão também recusa' do
      crase = com_campo('campo' => 'configuracoes.a', 'tipo' => 'texto', 'origem' => 'cliente', 'descricao' => 'Use `x`.')
      travessao = com_campo('campo' => 'configuracoes.b', 'tipo' => 'texto', 'origem' => 'cliente', 'descricao' => 'Sim — ou não.')

      expect(recusa(crase)).to include('configuracoes.a com crase ou travessao')
      expect(recusa(travessao)).to include('configuracoes.b com crase ou travessao')
    end

    it 'valores que não cabem no tipo e campo fora de grupo recusam' do
      letra = com_campo('campo' => 'configuracoes.c', 'tipo' => 'numero', 'origem' => 'cliente', 'descricao' => 'x',
                        'valores' => { 'S' => 'Sim' })
      raiz = com_campo('campo' => 'solto', 'tipo' => 'texto', 'origem' => 'cliente', 'descricao' => 'x')

      expect(recusa(letra)).to include('configuracoes.c com valores fora do tipo')
      expect(recusa(raiz)).to include('solto fora de grupo')
    end

    it 'campo derivado ou escolha sem descrição não recusa: ele não é pergunta' do
      derivado = com_campo('campo' => 'configuracoes.d', 'tipo' => 'texto', 'origem' => 'derivado')

      expect { described_class.do_ramo(derivado) }.not_to raise_error
    end
  end

  it 'auto não muda: de_auto continua expondo as três origens, sem enum' do
    auto = described_class.de_auto(Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO)
    propriedades = auto.flat_map { |g| g['properties'] }

    expect(propriedades.size).to eq(Autonomia::Insurance::Connector::Mock::SCHEMA_AUTO['campos'].size - 2)
    expect(propriedades).to all(satisfy { |p| !p.key?('enum') })
  end

  it 'sem schema, não há grupo nenhum' do
    expect(described_class.do_ramo(nil)).to eq([])
  end
end

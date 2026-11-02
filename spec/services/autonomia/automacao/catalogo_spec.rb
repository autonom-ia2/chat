require 'rails_helper'

# O CI cobra o catálogo de passos da Automação livre (#2414 F5, ADR-001 2.2): o arquivo gerado está em dia, toda ação
# liberada tem lugar no editor ou fica só no Guia com motivo, todo campo tem peça da tela ou está escondido, e toda
# frase existe em pt_BR e en.
RSpec.describe Autonomia::Automacao::Catalogo do
  let(:catalogo) { described_class }
  let(:declarado) { catalogo.declarado }
  let(:permitidas) { Autonomia::Automacao::AcoesPermitidas }
  let(:passos) { catalogo.gerado['passos'] }
  let(:acoes) { passos.select { |passo| passo['tipo'] == 'acao' } }

  def frases(locale)
    JSON.parse(Rails.root.join("app/javascript/dashboard/i18n/locale/#{locale}/automacaoLivre.json").read)
  end

  # Os campos que a ação aceita, com o de dentro pelo ponto: "custom_attribute_definition.attribute_values".
  def campos_do_formato(campos, prefixo = nil)
    campos.to_h.flat_map do |nome, regra|
      cheio = [prefixo, nome].compact.join('.')
      regra['campos'].present? ? campos_do_formato(regra['campos'], cheio) : [cheio]
    end
  end

  it 'está em dia com o código' do
    expect(catalogo.fora_de_dia?).to be(false), 'rode `bundle exec rails autonomia:guia:automacao` e envie o resultado'
  end

  it 'põe toda ação liberada no editor ou só no Guia, uma vez, e nada além delas' do
    no_editor = declarado['acoes'].values.pluck('acao')
    so_guia = declarado['so_guia'].keys

    expect((no_editor + so_guia).tally.select { |_acao, vezes| vezes > 1 }).to be_empty
    expect((no_editor + so_guia).sort).to eq(permitidas.acoes.keys.sort)
    expect(declarado['so_guia'].values).to all(be_present)
  end

  it 'só traz ação liberada: nenhum DELETE, nada de recurso sempre fora' do
    no_catalogo = acoes.pluck('acao')

    expect(no_catalogo - permitidas.acoes.keys).to be_empty
    expect(no_catalogo.select { |acao| acao.start_with?('DELETE ') }).to be_empty
    expect(no_catalogo.map { |acao| permitidas.recurso_de(acao) } & permitidas.sempre_fora).to be_empty
  end

  it 'para o rake quando o yml cita ação fora da lista ou sem formato' do
    expect { catalogo.formato_da_acao('x', 'DELETE agents/:id') }.to raise_error(ArgumentError, /não está liberada/)
    allow(permitidas).to receive(:permitida?).and_return(true)
    expect { catalogo.formato_da_acao('x', 'POST nao/existe') }.to raise_error(ArgumentError, /não existe/)
  end

  it 'mostra ou esconde cada campo da ação; proibido e fixo ficam de fora sozinhos' do
    declarado['acoes'].each do |nome, passo|
      formato = Autonomia::Guide::Formatos.para(passo['acao'])
      fora = permitidas.proibe(passo['acao']) + permitidas.fixos(passo['acao']).keys
      esperados = campos_do_formato(formato['campos']).reject { |campo| fora.include?(campo) }
      mostrados = passo['campos'].keys
      escondidos = Array(passo['escondidos'])

      expect(mostrados & escondidos).to be_empty, "#{nome}: campo mostrado e escondido"
      expect((mostrados + escondidos).sort).to eq(esperados.sort), "#{nome}: campos fora do formato de #{passo['acao']}"
      expect(permitidas.exige(passo['acao']) - mostrados).to be_empty, "#{nome}: campo exigido escondido"
    end
  end

  it 'usa peça que existe e serve para o tipo do campo; escolha traz as opções' do
    acoes.each do |passo|
      formato = Autonomia::Guide::Formatos.para(passo['acao'])
      passo['campos'].each do |campo|
        tipos = catalogo::PECAS[campo['peca']]
        tipo = catalogo.formato_do_campo(formato, campo['nome'])['tipo']

        expect(tipos).to be_present, "#{passo['nome']}.#{campo['nome']}: peça #{campo['peca']} não existe"
        expect(tipo.nil? || tipos.include?(tipo)).to be(true), "#{passo['nome']}.#{campo['nome']}: #{campo['peca']} não serve para #{tipo}"
        expect(campo['opcoes']).to be_present, "#{passo['nome']}.#{campo['nome']}: escolha sem opções" if campo['peca'] == 'escolha'
      end
    end
  end

  it 'dá origem a todo parâmetro do caminho: um valor do alvo ou uma escolha na tela' do
    acoes.each do |passo|
      parametros = passo['acao'].split('/').filter_map { |parte| parte.delete_prefix(':') if parte.start_with?(':') }

      expect(passo['caminho'].keys.sort).to eq(parametros.sort), "#{passo['nome']}: caminho incompleto"
      passo['caminho'].each_value do |origem|
        valido = Autonomia::Automacao::Valores::CAMPOS.key?(origem['$valor']) || catalogo::ESCOLHAS.include?(origem['escolher'])
        expect(valido).to be(true), "#{passo['nome']}: origem #{origem} desconhecida"
      end
    end
  end

  it 'dá grupo e peça a todo passo nativo do esquema' do
    nativos = passos.reject { |passo| passo['tipo'] == 'acao' }

    expect(nativos.pluck('tipo')).to contain_exactly('esperar', 'esperar_ate', 'se', 'parar')
    expect(nativos.flat_map { |passo| passo['campos'] }.pluck('peca')).to all(be_present)
    expect(passos.pluck('grupo') - declarado['grupos']).to be_empty
  end

  it 'tem a frase de tudo em pt_BR e en' do
    chaves = []
    coletar = lambda do |valor|
      case valor
      when Hash then valor.each { |chave, item| %w[frase rotulo].include?(chave) ? chaves << item : coletar.call(item) }
      when Array then valor.each { |item| coletar.call(item) }
      end
    end
    coletar.call(catalogo.gerado)

    %w[pt_BR en].each do |locale|
      catalogo_do_locale = frases(locale)
      faltando = chaves.uniq.reject { |chave| catalogo_do_locale.dig(*chave.split('.')).is_a?(String) }
      expect(faltando).to be_empty, "#{locale} sem: #{faltando.join(', ')}"
    end
  end
end

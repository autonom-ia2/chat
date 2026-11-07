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
    # Um arquivo por área (#2569), juntos no mesmo AUTOMACAO_LIVRE como no index do painel.
    Rails.root.glob("app/javascript/dashboard/i18n/locale/#{locale}/automacaoLivre*.json")
         .map { |arquivo| JSON.parse(arquivo.read) }
         .reduce { |juntos, area| juntos.merge(area) { |_namespace, um, outro| um.merge(outro) } }
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

    expect(nativos.pluck('tipo')).to contain_exactly('esperar', 'esperar_ate', 'se', 'parar', 'mensagem', 'avisar', 'email',
                                                     'decidir', 'extrair', 'escrever', 'resumir', 'ia_assumir', 'retorno',
                                                     'em_outro_registro')
    expect(nativos.flat_map { |passo| passo['campos'] }.pluck('peca')).to all(be_present)
    expect(passos.pluck('grupo') - declarado['grupos']).to be_empty
  end

  # A tela esconde o passo sem a flag; a flag tem que existir, senão o passo some de todas as contas sem aviso.
  it 'só pede flag que existe, e mensagem, avisar e email pedem a da F4' do
    flags = YAML.load_file(Rails.root.join('config/features.yml')).pluck('name')
    requer = passos.filter_map { |passo| passo['requer'] }
    da_f4 = %w[mensagem avisar email]

    expect(requer - flags).to be_empty
    expect(passos.select { |passo| da_f4.include?(passo['tipo']) }.pluck('requer'))
      .to eq([Autonomia::Automacao::Motor::FLAG_MENSAGENS] * 3)
  end

  it 'põe todo passo nativo do esquema no editor ou fora dele com motivo, uma vez' do
    do_esquema = catalogo.esquema.dig('definitions', 'passo', 'oneOf').map { |forma| forma.dig('properties', 'tipo', 'const') } - ['acao']
    fora = declarado['nativos_fora_do_editor'].to_h

    expect((declarado['nativos'].keys + fora.keys).sort).to eq(do_esquema.sort)
    # Cada um com a Issue que o leva para a tela (o primeiro foi a #2486, de mensagem e avisar).
    expect(fora.values).to all(include('(#'))
  end

  # #2496: todo valor da mensagem do gatilho está no editor ou só no Guia, uma vez. O que fica de fora do catálogo
  # passaria pela troca de gatilho sem sair do "Só se", e o salvar recusaria sem a tela avisar.
  it 'põe todo valor da mensagem do gatilho no editor ou só no Guia, com as opções do valor fechado', :aggregate_failures do
    valores = Autonomia::Automacao::Valores
    declarados = declarado['valores_do_gatilho'] + declarado['valores_so_guia'].keys
    da_mensagem = catalogo.gerado['valores'].select { |valor| valor['so_no_gatilho'] }

    expect(declarados).to match_array(valores::MENSAGEM.keys)
    expect(declarado['valores_so_guia'].values).to all(be_present)
    expect(da_mensagem.pluck('caminho')).to match_array(valores::MENSAGEM.keys)
    da_mensagem.each do |valor|
      expect(valor['opcoes'].pluck('valor')).to eq(valores.fechado(valor['caminho'])['opcoes'])
      expect(valor['operadores'].pluck('op')).to eq(valores.fechado(valor['caminho'])['operadores'])
    end
  end

  # #2527: o valor fechado do alvo (quem começou a conversa) vai ao editor com as opções, como os da mensagem; sem
  # elas, a pessoa digitaria "Cliente" e o salvar recusaria.
  it 'dá ao valor fechado do alvo as opções e os operadores dele' do
    valor = catalogo.gerado['valores'].find { |item| item['caminho'] == 'conversa.iniciada_por' }

    expect(valor).to include('base' => 'conversa', 'opcoes' => [
                               { 'valor' => 'cliente', 'frase' => 'AUTOMACAO_LIVRE.VALOR_DA_MENSAGEM.CLIENTE' },
                               { 'valor' => 'equipe', 'frase' => 'AUTOMACAO_LIVRE.VALOR_DA_MENSAGEM.EQUIPE' }
                             ])
    expect(valor['operadores'].pluck('op')).to eq(%w[igual diferente])
  end

  # G11: a resposta durante a espera vai ao catálogo como valor do alvo, sim/não, marcada para o editor só a oferecer
  # na condição do "esperar até"; nunca como valor da mensagem do gatilho.
  it 'leva a resposta durante a espera como valor do alvo, só para o "esperar até"', :aggregate_failures do
    respostas = catalogo.gerado['valores'].select { |item| item['so_na_espera'] }

    expect(respostas.pluck('caminho')).to eq(%w[conversa.cliente_respondeu conversa.equipe_respondeu])
    expect(respostas).to all(include('base' => 'conversa'))
    expect(respostas).to all(satisfy { |item| item['so_no_gatilho'].nil? && item['opcoes'].pluck('valor') == [true, false] })
  end

  # A condição que o editor já põe ao escolher o gatilho tem que salvar.
  it 'sugere filtro que a Receita aceita no próprio gatilho' do
    catalogo.gerado['gatilhos'].select { |gatilho| gatilho['filtro_sugerido'] }.each do |gatilho|
      receita = { 'gatilho' => { 'tipo' => gatilho['tipo'], 'filtros' => [gatilho['filtro_sugerido']] },
                  'passos' => [{ 'id' => 'p1', 'tipo' => 'parar' }] }

      expect(Autonomia::Automacao::Receita.esquema_valido?(receita)).to be(true)
      expect(Autonomia::Automacao::Receita.new(receita, conta: create(:account), account_user: nil).problemas).to be_empty
    end
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

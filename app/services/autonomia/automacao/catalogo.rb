# O catálogo de passos da Automação livre (#2414 F5, ADR-001 2.2): o arquivo que o editor e o Guia leem.
#
# Junta três fontes num JSON só (lib/operator_guide/automacao-passos.json):
# - o esquema da receita: gatilhos, operadores, unidades de tempo e os passos nativos (esperar, se, parar, mensagem, avisar);
# - o catálogo do Guia (formatos-das-acoes.json): o tipo, as opções e os limites de cada campo das ações liberadas;
# - automacao-passos.yml: o nome do passo, o grupo, de onde vem cada parâmetro e a peça da tela de cada campo;
# - automacao-receitas.yml: as receitas prontas da porta da nova (#2498), com a flag que cada uma pede.
# A frase de cada coisa é uma chave do i18n do painel (automacaoLivre.json), conferida pelo spec do CI.
module Autonomia::Automacao::Catalogo
  ARQUIVO = Rails.root.join('lib/operator_guide/automacao-passos.json')
  DECLARADO = Rails.root.join('lib/operator_guide/automacao-passos.yml')
  RECEITAS = Rails.root.join('lib/operator_guide/automacao-receitas.yml')
  I18N = 'AUTOMACAO_LIVRE'.freeze

  # A peça da tela que mostra cada campo e os tipos do catálogo do Guia que ela aceita. Campo sem tipo no catálogo
  # (o Guia não soube dizer) aceita qualquer peça.
  PECAS = {
    'texto' => %w[string],
    'cor' => %w[string],
    'escolha' => %w[string],
    'sim_nao' => %w[booleano],
    'data_hora' => %w[data_hora],
    'lista_de_textos' => %w[lista],
    'pessoa' => %w[inteiro],
    'time' => %w[inteiro],
    'caixa' => %w[inteiro],
    'empresa' => %w[inteiro],
    'pessoas' => %w[lista],
    'etiquetas' => %w[lista],
    'atributos_da_conversa' => %w[objeto_livre],
    'atributos_do_contato' => %w[objeto_livre],
    'atributos_da_empresa' => %w[objeto_livre]
  }.freeze

  # Obrigatório sempre. "condicional" (só em certos casos) não marca o campo na tela: a Receita confere ao salvar.
  OBRIGATORIO = [true, 'pelo_modelo'].freeze

  # O que a pessoa escolhe na tela para um parâmetro do caminho.
  ESCOLHAS = %w[etiqueta atributo].freeze

  # As peças dos passos nativos: a definição do esquema que cada propriedade usa.
  PECAS_DO_ESQUEMA = { 'duracao' => 'duracao', 'condicao' => 'condicao', 'passos' => 'passos',
                       'passos_opcionais' => 'passos', 'texto' => 'texto_com_valores',
                       # F7: os passos de IA.
                       'leituras' => 'leituras', 'instrucao' => 'instrucao', 'caminhos' => 'caminhos',
                       'campos_extrair' => 'campos_extrair', 'destino_escrever' => 'destino_escrever',
                       'destino_resumir' => 'destino_resumir' }.freeze
  # A propriedade descrita ali mesmo no esquema, sem definição própria: quem recebe o "avisar".
  PECAS_SEM_DEFINICAO = { 'para' => 'destinatarios', 'trocar' => 'sim_nao', 'linhas' => 'numero' }.freeze

  module_function

  def todos
    @todos ||= JSON.parse(ARQUIVO.read).freeze
  end

  def gerado
    {
      'gatilhos' => gatilhos,
      'operadores' => operadores,
      'unidades' => unidades,
      'valores' => valores,
      # O que cada alvo de gatilho alcança (#2499): o editor só oferece o valor dessas bases.
      'alvos' => ::Autonomia::Automacao::Valores::BASES_DO_ALVO,
      'grupos' => declarado['grupos'].map { |grupo| { 'chave' => grupo, 'frase' => chave('GRUPOS', grupo) } },
      'passos' => nativos + acoes,
      'receitas' => receitas
    }
  end

  # #2498: cada receita pronta com a frase da porta e as flags que os passos dela pedem (a porta mostra o porquê).
  def receitas
    YAML.safe_load_file(RECEITAS).map do |nome, item|
      tipos = ::Autonomia::Automacao::Receita.new(item['receita'], conta: nil).passos.pluck('tipo')
      requer = tipos.filter_map { |tipo| declarado.dig('nativos', tipo, 'requer') }.uniq
      { 'chave' => nome, 'frase' => chave('RECEITAS', nome, 'TITULO'), 'requer' => requer, 'receita' => item['receita'] }
    end
  end

  def escrever!
    ARQUIVO.write("#{JSON.pretty_generate(gerado)}\n")
    @todos = nil
  end

  def fora_de_dia?
    !ARQUIVO.exist? || JSON.parse(ARQUIVO.read) != JSON.parse(gerado.to_json)
  end

  def declarado
    @declarado ||= YAML.safe_load_file(DECLARADO).freeze
  end

  def esquema
    ::Autonomia::Automacao::Receita::ESQUEMA
  end

  def chave(*partes)
    [I18N, *partes.map { |parte| parte.to_s.tr('.', '_').upcase }].join('.')
  end

  def gatilhos
    esquema.dig('properties', 'gatilho', 'properties', 'tipo', 'enum').map do |tipo|
      { 'tipo' => tipo, 'alvo' => ::Autonomia::Automacao::Gatilhos.alvo(tipo), 'frase' => chave('GATILHOS', tipo),
        'filtro_sugerido' => declarado.dig('filtro_sugerido', tipo) }.compact
    end
  end

  def unidades
    esquema.dig('definitions', 'duracao', 'properties', 'unidade', 'enum').map do |unidade|
      { 'valor' => unidade, 'frase' => chave('UNIDADES', unidade) }
    end
  end

  # Cada operador e se ele pede um valor para comparar ("está vazio" não pede).
  def operadores
    esquema.dig('definitions', 'condicao', 'oneOf').filter_map do |forma|
      ops = forma.dig('properties', 'op', 'enum')
      ops&.map { |op| { 'op' => op, 'pede_valor' => forma['required'].include?('valor'), 'frase' => chave('OPERADORES', op) } }
    end.flatten
  end

  # O que a receita lê do alvo, para o editor mostrar como chip. Os atributos entram pela base mais a chave. A `base`
  # (conversa, contato, card) diz ao editor o que oferecer para o alvo do gatilho (#2499).
  def valores
    campos = ::Autonomia::Automacao::Valores::CAMPOS.keys.map do |caminho|
      { 'caminho' => caminho, 'base' => caminho.split('.').first, 'frase' => chave('VALORES', caminho) }
    end
    atributos = ::Autonomia::Automacao::Valores::MODELOS.map do |base, modelo|
      { 'caminho' => base, 'base' => base.split('.').first, 'atributos' => modelo, 'frase' => chave('VALORES', base) }
    end
    campos + atributos + valores_do_gatilho
  end

  # A mensagem do gatilho (#2496), com as opções e os operadores do valor fechado. A que só o Guia monta vem marcada:
  # a tela não a oferece, mas mostra a frase, abre a condição que já a usa e a tira do "Só se" quando o gatilho muda.
  def valores_do_gatilho
    so_guia = declarado['valores_so_guia'].keys
    (declarado['valores_do_gatilho'] + so_guia).map do |caminho|
      { **valor_da_mensagem(caminho), 'so_guia' => (true if so_guia.include?(caminho)) }.compact
    end
  end

  def valor_da_mensagem(caminho)
    valores = ::Autonomia::Automacao::Valores
    fechado = valores.fechado(caminho)
    { 'caminho' => caminho, 'frase' => chave('VALORES', caminho), 'so_no_gatilho' => valores::GATILHO_DA_MENSAGEM,
      'opcoes' => fechado['opcoes'].map { |opcao| { 'valor' => opcao, 'frase' => chave('VALOR_DA_MENSAGEM', opcao) } },
      'operadores' => fechado['operadores'].map { |op| { 'op' => op, 'frase' => chave('OPERADOR_DA_MENSAGEM', op) } } }
  end

  def nativos
    esquema.dig('definitions', 'passo', 'oneOf').filter_map do |forma|
      tipo = forma.dig('properties', 'tipo', 'const')
      next if tipo == 'acao' || declarado['nativos_fora_do_editor'].to_h.key?(tipo)

      { 'tipo' => tipo, 'grupo' => declarado.dig('nativos', tipo, 'grupo'), 'requer' => declarado.dig('nativos', tipo, 'requer'),
        'frase' => chave('PASSOS', tipo), 'campos' => campos_nativos(forma) }.compact
    end
  end

  def campos_nativos(forma)
    forma['properties'].except('id', 'tipo').map do |nome, propriedade|
      peca = PECAS_DO_ESQUEMA[propriedade['$ref'].to_s.split('/').last] || PECAS_SEM_DEFINICAO[nome]
      { 'nome' => nome, 'peca' => peca,
        'obrigatorio' => forma['required'].include?(nome), 'rotulo' => chave('CAMPOS', nome) }
    end
  end

  def acoes
    declarado['acoes'].map do |nome, passo|
      formato = formato_da_acao(nome, passo['acao'])
      { 'tipo' => 'acao', 'nome' => nome, 'acao' => passo['acao'], 'grupo' => passo['grupo'], 'frase' => chave('PASSOS', nome),
        'caminho' => passo['caminho'].to_h.transform_values { |origem| origem_do_parametro(origem) },
        'envelope' => (formato['envelope'] unless formato['corpo_plano']),
        'fixos' => ::Autonomia::Automacao::AcoesPermitidas.fixos(passo['acao']),
        'campos' => passo['campos'].map { |campo, peca| campo_da_acao(passo['acao'], formato, campo, peca) } }.compact
    end
  end

  # O catálogo é só apresentação: quem autoriza é a Versao, pela Receita. Mas ação do yml que não está liberada ou sumiu
  # do catálogo do Guia é erro de quem escreveu o yml, e o rake para em vez de gerar sem ela.
  def formato_da_acao(nome, acao)
    raise ArgumentError, "#{nome}: #{acao} não está liberada em automacao-recursos.yml" unless
      ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)

    ::Autonomia::Guide::Formatos.para(acao) || raise(ArgumentError, "#{nome}: #{acao} não existe em formatos-das-acoes.json")
  end

  def origem_do_parametro(origem)
    return { '$valor' => origem } unless origem.is_a?(Hash)

    { 'escolher' => origem['escolher'], 'rotulo' => chave('ESCOLHER', origem['escolher']) }
  end

  def campo_da_acao(acao, formato, campo, peca)
    regra = formato_do_campo(formato, campo)
    {
      'nome' => campo, 'peca' => peca, 'rotulo' => chave('CAMPOS', campo.split('.').last),
      'obrigatorio' => OBRIGATORIO.include?(regra['obrigatorio']) || ::Autonomia::Automacao::AcoesPermitidas.exige(acao).include?(campo),
      'opcoes' => regra['um_de']&.map { |valor| { 'valor' => valor, 'frase' => chave('OPCOES', campo.split('.').last, valor) } },
      **regra.slice('padrao', 'min', 'max', 'max_caracteres')
    }.compact
  end

  # "custom_attribute_definition.attribute_values" lê o campo de dentro.
  def formato_do_campo(formato, campo)
    campo.split('.').reduce(formato) { |nivel, parte| nivel.to_h.dig('campos', parte) }.to_h
  end
end

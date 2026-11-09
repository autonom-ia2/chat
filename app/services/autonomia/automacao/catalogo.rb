# O catálogo de passos da Automação livre (#2414 F5, ADR-001 2.2): o arquivo que o editor e o Guia leem.
#
# Junta três fontes num JSON só (lib/operator_guide/automacao-passos.json):
# - o esquema da receita: gatilhos, operadores, unidades de tempo e os passos nativos (esperar, se, parar, mensagem, avisar, email);
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
  # `prazo_da_espera` (#2750): a duração ou "sem prazo", do "esperar até".
  PECAS_DO_ESQUEMA = { 'duracao' => 'duracao', 'prazo_da_espera' => 'prazo', 'condicao' => 'condicao', 'passos' => 'passos',
                       'passos_opcionais' => 'passos', 'texto' => 'texto_com_valores', 'linha' => 'linha_com_valores',
                       # F7: os passos de IA.
                       'leituras' => 'leituras', 'instrucao' => 'instrucao', 'caminhos' => 'caminhos',
                       'campos_extrair' => 'campos_extrair', 'destino_escrever' => 'destino_escrever',
                       # F4b (#2468): o modelo da Meta do passo "mensagem".
                       'destino_resumir' => 'destino_resumir', 'modelo_whatsapp' => 'modelo_whatsapp',
                       # G15: a agente de IA que assume a conversa.
                       'agente_de_ia' => 'agente_de_ia',
                       # G3 (#2629): o "criar retorno".
                       'para_do_retorno' => 'quem_recebe_retorno', 'envio_do_retorno' => 'envio_do_retorno',
                       # G31: o "decidir" que espera a próxima resposta e decide de novo.
                       'de_novo' => 'de_novo' }.freeze
  # A propriedade descrita ali mesmo no esquema, sem definição própria: quem recebe o "avisar", a caixa do "email" (G2), a
  # etapa do "card" (G4) e a hora da conferência do "esperar até" sem prazo (G64, mostrada pela peça do prazo).
  # O "Cobrir a pessoa enquanto ela não responde" do "Passar para a agente de IA" (decisão 18) é um sim/não.
  PECAS_SEM_DEFINICAO = { 'para' => 'destinatarios', 'trocar' => 'sim_nao', 'linhas' => 'numero', 'caixa_id' => 'caixa_de_email',
                          'etapa_id' => 'etapa', 'conferir_as' => 'conferir_as', 'cobrir_pessoa' => 'sim_nao' }.freeze

  module_function

  def todos
    @todos ||= JSON.parse(ARQUIVO.read).freeze
  end

  def gerado
    {
      'gatilhos' => gatilhos,
      'operadores' => operadores,
      'unidades' => unidades,
      'valores' => ::Autonomia::Automacao::CatalogoDeValores.todos,
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
      tipos = ::Autonomia::Automacao::Receita.new(item['receita'], conta: nil, account_user: nil).passos.pluck('tipo')
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

  # O que sai do esquema da receita: os gatilhos, as unidades de tempo e os operadores.
  def gatilhos = ::Autonomia::Automacao::CatalogoDoEsquema.gatilhos(esquema, declarado)
  def unidades = ::Autonomia::Automacao::CatalogoDoEsquema.unidades(esquema)
  def operadores = ::Autonomia::Automacao::CatalogoDoEsquema.operadores(esquema)

  def nativos
    esquema.dig('definitions', 'passo', 'oneOf').filter_map do |forma|
      tipo = forma.dig('properties', 'tipo', 'const')
      next if tipo == 'acao' || declarado['nativos_fora_do_editor'].to_h.key?(tipo)

      { 'tipo' => tipo, 'grupo' => declarado.dig('nativos', tipo, 'grupo'), 'requer' => declarado.dig('nativos', tipo, 'requer'),
        'funil' => declarado.dig('nativos', tipo, 'funil'), 'frase' => chave('PASSOS', tipo),
        'campos' => campos_nativos(forma, declarado.dig('nativos', tipo, 'peca'), declarado.dig('nativos', tipo, 'rotulos')) }.compact
    end
  end

  # `peca` no yml (a campanha, G14): uma peça só mostra o passo inteiro. `rotulos` (G41): o rótulo próprio de um campo
  # neste passo.
  def campos_nativos(forma, peca_do_passo = nil, rotulos = nil)
    forma['properties'].except('id', 'tipo').map do |nome, propriedade|
      peca = peca_do_passo || PECAS_DO_ESQUEMA[propriedade['$ref'].to_s.split('/').last] || PECAS_SEM_DEFINICAO[nome]
      { 'nome' => nome, 'peca' => peca,
        'obrigatorio' => forma['required'].include?(nome), 'rotulo' => chave('CAMPOS', rotulos.to_h[nome] || nome) }
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

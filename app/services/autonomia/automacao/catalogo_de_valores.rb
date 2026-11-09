# Os valores do catálogo de passos (Autonomia::Automacao::Catalogo): o que a receita lê do alvo e da mensagem do
# gatilho, com as frases e, no valor fechado, as opções e os operadores. Saiu do Catalogo para ele caber no tamanho.
module Autonomia::Automacao::CatalogoDeValores
  module_function

  def chave(*partes) = ::Autonomia::Automacao::Catalogo.chave(*partes)
  def declarado = ::Autonomia::Automacao::Catalogo.declarado

  # O que a receita lê do alvo, para o editor mostrar como chip. Os atributos entram pela base mais a chave. A `base`
  # (conversa, contato, card) diz ao editor o que oferecer para o alvo do gatilho (#2499). A resposta durante a espera
  # (G11) vem marcada `so_na_espera`: o editor só a oferece na condição do "esperar até". A reunião (G12) vem com
  # `so_nos_gatilhos`: o editor só a oferece nos gatilhos de reunião. O que era antes da troca (G9), só no gatilho da
  # troca.
  def todos
    valores = ::Autonomia::Automacao::Valores
    campos = caminhos_dos_campos(valores).map do |caminho|
      { 'caminho' => caminho, 'base' => caminho.split('.').first, 'frase' => chave('VALORES', caminho), **do_fechado(caminho),
        **do_protegido(caminho), 'so_na_espera' => (true if valores.da_resposta?(caminho)),
        'so_nos_gatilhos' => valores.so_nos_gatilhos(caminho) }.compact
    end
    atributos = ::Autonomia::Automacao::Valores::MODELOS.map do |base, modelo|
      { 'caminho' => base, 'base' => base.split('.').first, 'atributos' => modelo, 'frase' => chave('VALORES', base) }
    end
    campos + atributos + valores_do_gatilho
  end

  # A mensagem do gatilho (#2496), com as opções e os operadores do valor fechado. A que só o Guia monta vem marcada:
  # a tela não a oferece, mas mostra a frase, abre a condição que já a usa e a tira do "Só se" quando o gatilho muda.
  # Os valores de leitura direta: os campos, os que dependem de quem vê, a agenda, a resposta, o envio e a troca.
  def caminhos_dos_campos(valores)
    valores::CAMPOS.keys + valores::DO_QUE_QUEM_VE.keys + valores::AGENDA.keys + valores::RESPOSTA.keys + valores::ENVIO.keys +
      valores::TROCA.keys
  end

  def valores_do_gatilho
    so_guia = declarado['valores_so_guia'].keys
    (declarado['valores_do_gatilho'] + so_guia).map do |caminho|
      { **valor_da_mensagem(caminho), 'so_guia' => (true if so_guia.include?(caminho)) }.compact
    end
  end

  def valor_da_mensagem(caminho)
    { 'caminho' => caminho, 'frase' => chave('VALORES', caminho),
      'so_no_gatilho' => ::Autonomia::Automacao::Valores::GATILHO_DA_MENSAGEM, **do_fechado(caminho) }
  end

  # As opções e os operadores do valor fechado (#2496), da mensagem ou do alvo (`conversa.iniciada_por`, #2527). As
  # frases ficam em VALOR_DA_MENSAGEM e OPERADOR_DA_MENSAGEM para todos os fechados.
  def do_fechado(caminho)
    fechado = ::Autonomia::Automacao::Valores.fechado(caminho)
    return {} unless fechado

    { 'opcoes' => fechado['opcoes'].map { |opcao| { 'valor' => opcao, 'frase' => chave('VALOR_DA_MENSAGEM', opcao) } },
      'operadores' => fechado['operadores'].map { |op| { 'op' => op, 'frase' => chave('OPERADOR_DA_MENSAGEM', op) } } }
  end

  # O valor que pede permissão (#2597) leva a chave: o editor não o oferece a quem não a tem. Quem autoriza continua
  # sendo a Receita, ao salvar, e o Valores, ao rodar.
  def do_protegido(caminho)
    regra = ::Autonomia::Automacao::Valores::PROTEGIDOS[caminho]
    regra ? { 'permissao' => regra::CHAVE } : {}
  end
end

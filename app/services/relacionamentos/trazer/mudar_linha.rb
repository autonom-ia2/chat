# A pessoa mexeu numa linha com problema na conferência de "Trazer minha lista" (#2896): consertou, deixou de fora ou
# voltou atrás. Tudo sob a trava da importação, e só enquanto a leitura está pronta: com a planilha sendo lida de novo,
# ou depois de trazida, o pedido é recusado.
#
# - Consertar: o valor perde os caracteres de controle (o byte nulo inclusive) e é conferido com os mesmos leitores da
#   leitura (ContactImports::Trazer::Conserto). O valor que não vale é recusado (`valor_invalido`, com o motivo). O que
#   vale fica guardado no arquivo dos consertos (ContactImports::Trazer::Consertos), o único lugar onde o valor digitado
#   existe, junto com a coluna em que foi feito. Se a linha ainda tem outro problema, ela continua aberta, agora com o
#   problema que sobrou.
# - A linha do tipo `formula` (o erro está num campo que a tela não conserta) recusa qualquer valor, com
#   `formula_detected`: ela só pode ficar de fora.
# - Linha repetida: `ficar_com` diz com qual das linhas a pessoa fica. Com a outra, esta é deixada de fora. Com esta, a
#   outra (que estava aprovada) sai na hora de trazer, e as demais repetidas da mesma pessoa ficam de fora, inclusive a
#   que a pessoa tinha escolhido antes: de um grupo de linhas da mesma pessoa entra uma só.
# - Deixar de fora e voltar atrás esquecem o que tinha sido consertado na linha.
# - Na planilha que traz seguros (E4, #2897), a linha com problema no seguro (Carteira::Trazer::ProblemasDeSeguro)
#   recusa qualquer valor, com `conserto_na_planilha`: ela só pode ficar de fora. A exceção é a mesma apólice em duas
#   linhas (`duplicado`): a pessoa escolhe com qual fica, com o mesmo `ficar_com` da linha repetida.
#
# Devolve a linha como a tela a mostra agora (`problema`), quantas pessoas entram se a pessoa mandar trazer agora
# (`entram`) e quantas delas como cliente (`clientes`): as contas de ContactImports::Trazer::QuemEntra, as do resumo.
#
# Cada pedido regrava só o arquivo dos consertos, que tem o tamanho dos consertos, não o da planilha, e lê cada arquivo
# da conferência uma vez só: os dois leitores são criados aqui e passados adiante. O arquivo conferido só é mexido na
# hora de trazer (ContactImports::Trazer::FecharConferencia). A linha no banco continua como problema até lá: a tela
# segue mostrando a linha, agora guardada ou deixada.
class Relacionamentos::Trazer::MudarLinha
  Resultado = Struct.new(:erro, :motivo, :problema, :entram, :clientes, keyword_init: true)
  FICAR_COM = ContactImports::Trazer::Conserto::FICAR_COM
  CONTATO = ContactImports::Trazer::Conserto::CONTATO
  CAMPO_DO_TIPO = { 'telefone' => 'telefone', 'email' => 'email', 'nome' => 'nome', 'sem_contato' => CONTATO }.freeze
  REPETIDA = 'duplicada'.freeze
  DoSeguro = Carteira::Trazer::ProblemasDeSeguro
  # A mesma pessoa em duas linhas e a mesma apólice em duas linhas: nas duas a pessoa escolhe com qual fica.
  REPETIDAS = [REPETIDA, DoSeguro::TIPO_DUPLICADO].freeze
  TETO_DO_VALOR = 255
  AVISO = ContactImports::Trazer::DesfazerMudanca::AVISO

  def initialize(importacao, numero)
    @importacao = importacao
    @numero = Integer(numero.to_s, 10, exception: false)
    @arquivo = ContactImports::Trazer::LinhasComProblema.new(importacao)
    @arquivo_dos_consertos = ContactImports::Trazer::Consertos.new(importacao)
  end

  # valor: o que a pessoa escreveu; ficar_com: o número da linha que fica, na linha repetida.
  def consertar(valor: nil, ficar_com: nil)
    valor = Relacionamentos::Trazer::Texto.sem_controle(valor) unless valor.nil?
    sob_a_trava do
      # Ficar com uma linha repetida mexe no grupo inteiro: o arquivo é lido de uma vez, e não duas.
      @arquivo.ler_tudo if ficar_com
      next Resultado.new(erro: 'planilha_apagada') if entrada.nil?

      sem_conserto(valor) || conferir_o_pedido(valor, ficar_com)
    end
  end

  def deixar_de_fora
    sob_a_trava { guardar(nil, deixada: true) }
  end

  def reabrir
    sob_a_trava { guardar(nil) }
  end

  private

  # A linha como ficou é montada depois da trava, com o que os dois leitores já têm na mão: nenhum arquivo é aberto de
  # novo.
  def sob_a_trava
    resultado = @importacao.with_lock do
      erro = erro_do_pedido
      erro ? Resultado.new(erro: erro) : yield
    end
    resultado.erro ? resultado : Resultado.new(problema: problema, **quem_entra.contas)
  end

  def erro_do_pedido
    return ContactImports::Trazer::Conferencia::VENCIDA if ContactImports::Trazer::Conferencia.vencida?(@importacao)
    return 'leitura_nao_pronta' unless @importacao.ready_to_confirm?

    'linha_desconhecida' if linha.nil?
  end

  def linha
    @linha ||= @numero && @importacao.campaign_import_rows.status_invalid.find_by(row_number: @numero)
  end

  def conferir_o_pedido(valor, ficar_com)
    return ficar_com_a_linha(Integer(ficar_com.to_s, 10, exception: false)) if REPETIDAS.include?(tipo)

    conferir(CAMPO_DO_TIPO.fetch(tipo), valor)
  end

  def ficar_com_a_linha(escolhida)
    outra = entrada.dig('outra', 'linha')
    return invalido('linha_desconhecida') unless outra && [@numero, outra].include?(escolhida)
    return guardar(nil, deixada: true) if escolhida == outra

    conferir(FICAR_COM, nil, outra: outra, fora: @arquivo.repetidas_de(outra) - [@numero])
  end

  # fora: as outras linhas repetidas da mesma pessoa, que deixam de entrar quando esta fica.
  def conferir(campo, valor, outra: nil, fora: [])
    feito = consertos[@numero].to_h
    conferidor = ContactImports::Trazer::Conserto.da_importacao(@importacao)
    conserto = conferidor.call(@numero, entrada['celulas'], campo: campo, valor: valor, valores: feito['valores'].to_h)
    return invalido(conserto.motivo) if conserto.motivo

    colunas = conserto.valores.keys.index_with { |alvo| conferidor.alvos[alvo] }
    guardar({ 'linha' => @numero, 'campo' => campo, 'outra' => outra || feito['outra'], 'valores' => conserto.valores, 'colunas' => colunas,
              'conferida' => conserto.conferida, 'sobrou' => conserto.sobrou }.compact, fora: fora)
  end

  # O valor que nem chega a ser conferido: longo demais, ou numa linha que a tela não conserta.
  def sem_conserto(valor)
    return invalido('muito_longo') if valor.to_s.length > TETO_DO_VALOR
    return invalido(DoSeguro::NA_PLANILHA) if DoSeguro.sem_conserto?(tipo)

    invalido(ContactImports::Trazer::Conserto::FORMULA) if tipo == Relacionamentos::Trazer::Pendencia::TIPO_SEM_CONSERTO
  end

  def invalido(motivo)
    Resultado.new(erro: 'valor_invalido', motivo: motivo)
  end

  # feito: o que fica guardado da linha no arquivo dos consertos, ou nil para esquecer o que havia. fora: as linhas que
  # passam a ficar de fora junto, esquecendo o que tinham guardado.
  def guardar(feito, deixada: false, fora: [])
    novos = consertos.except(@numero, *fora)
    novos = novos.merge(@numero => feito) if feito
    @arquivo_dos_consertos.gravar(novos) unless novos == consertos
    conferencia = ContactImports::Trazer::Conferencia.new(@importacao)
    conferencia.gravar('deixadas' => ((conferencia.deixadas - [@numero]) | fora | (deixada ? [@numero] : [])).sort)
    conferencia.tirar(AVISO)
    Resultado.new
  end

  def tipo
    @tipo ||= problema[:tipo]
  end

  # A linha como a tela a mostra agora, com o estado e o valor guardado.
  def problema
    Relacionamentos::Trazer::Problemas.new(@importacao, pagina: 1, por_pagina: 1, arquivo: @arquivo, consertos: @arquivo_dos_consertos)
                                      .da_linha(linha)
  end

  def quem_entra
    ContactImports::Trazer::QuemEntra.new(@importacao, consertos)
  end

  def consertos
    @arquivo_dos_consertos.ler
  end

  def entrada
    @arquivo.ler([@numero])[@numero]
  end
end

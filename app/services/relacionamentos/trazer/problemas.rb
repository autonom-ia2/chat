# As linhas da planilha que precisam da pessoa (#2896), uma página por vez, no formato da tela: a linha, o tipo do
# problema em palavras da tela, o nome e o valor que está errado.
#
# Tudo sai de dois arquivos pequenos da conferência, lidos uma vez por resposta (quem já os tem na mão passa os dois
# leitores: `arquivo` e `consertos`); a planilha original e o arquivo conferido nunca são abertos aqui:
# - o valor inteiro vem do arquivo das linhas com problema (ContactImports::Trazer::LinhasComProblema). Depois que ele
#   é apagado vai a máscara que a linha guarda. O nome é a exceção: a leitura já o guarda inteiro na linha, e ele sai
#   inteiro com ou sem o arquivo. A linha repetida traz a outra linha da mesma pessoa, que a leitura guardou junto
#   dela. A linha sem nome traz o contato dela (`contato`);
# - o que a pessoa consertou vem do arquivo dos consertos (ContactImports::Trazer::Consertos).
#
# O tipo, o motivo e o campo saem de Relacionamentos::Trazer::Pendencia: dos motivos que a leitura gravou na linha e das
# células dela como estão agora. A linha aberta diz o `motivo` em código; a que tem o erro num campo que a tela não
# conserta (a fórmula na empresa) é direto do tipo `formula`, com o `campo` e sem `valor`, tenha ou não outro problema.
# Na linha em que a pessoa já consertou alguma coisa:
# - o conserto resolveu a linha inteira: `guardado`, com o tipo do que foi consertado por último e o valor como vai ser
#   gravado (`corrigido`) ou a linha com que a pessoa ficou (`ficar_com`);
# - ainda sobrou problema: `aberto`, com o tipo e o motivo do que sobrou (a linha sem nome que teve o telefone
#   consertado).
# A linha que a pessoa deixou de fora (ContactImports::Trazer::Conferencia) é `deixado`.
class Relacionamentos::Trazer::Problemas
  Pendencia = Relacionamentos::Trazer::Pendencia
  REPETIDA = Pendencia::REPETIDA
  ALVOS = CampaignImports::SpreadsheetReader::TARGETS
  ALVO_DO_TIPO = { 'telefone' => 'phone', 'email' => 'email', 'nome' => 'name' }.freeze
  NOME = Pendencia::NOME
  CONTATOS = %w[phone email].freeze
  FICAR_COM = ContactImports::Trazer::Conserto::FICAR_COM
  # O que a pessoa consertou por último => o tipo da linha guardada e onde está o valor na linha conferida.
  TIPO_DO_CAMPO = { 'telefone' => 'telefone', 'email' => 'email', 'nome' => NOME, 'contato' => 'sem_contato', FICAR_COM => 'duplicada' }.freeze
  CORRIGIDO = { 'telefone' => %w[phone_number], 'email' => %w[email], 'nome' => %w[name], 'contato' => %w[phone_number email] }.freeze
  GUARDADO = 'guardado'.freeze
  ABERTO = 'aberto'.freeze
  MASCARAS = { 'phone' => :raw_phone_masked, 'email' => :email_masked, 'name' => :raw_name }.freeze
  # O que a linha no banco também guarda inteiro: serve quando o arquivo das linhas com problema já foi apagado.
  NA_LINHA = { 'name' => :raw_name, 'company' => :company_name }.freeze

  # arquivo: ContactImports::Trazer::LinhasComProblema; consertos: ContactImports::Trazer::Consertos. Quem não passa
  # ganha um de cada.
  def initialize(importacao, pagina:, por_pagina:, arquivo: nil, consertos: nil)
    @importacao = importacao
    @pagina = pagina
    @por_pagina = por_pagina
    @arquivo = arquivo || ContactImports::Trazer::LinhasComProblema.new(importacao)
    @arquivo_dos_consertos = consertos || ContactImports::Trazer::Consertos.new(importacao)
  end

  def call
    linhas.map { |linha| problema(linha) }
  end

  # Uma linha só, fora da página: a resposta de quem acabou de mexer nela (Relacionamentos::Trazer::MudarLinha).
  def da_linha(linha)
    @linhas = [linha]
    problema(linha)
  end

  # Sem linha com problema não há valor para mascarar.
  def inteiros?
    @importacao.invalid_rows.zero? || arquivo.existe?
  end

  private

  def linhas
    @linhas ||= @importacao.campaign_import_rows.status_invalid.order(:row_number)
                           .offset((@pagina - 1) * @por_pagina).limit(@por_pagina).to_a
  end

  def problema(linha)
    feito = consertos[linha.row_number]
    estado = estado_de(linha.row_number, feito)
    pendencia = estado == GUARDADO ? Pendencia::Resultado.new(tipo: TIPO_DO_CAMPO.fetch(feito['campo'])) : pendencia_de(linha, feito)
    item = { linha: linha.row_number, tipo: pendencia.tipo, nome: linha.raw_name.to_s, estado: estado }.merge(do_tipo(linha, pendencia))
    item = item.merge(motivo: pendencia.motivo) if estado == ABERTO && pendencia.motivo
    estado == GUARDADO ? item.merge(guardado(linha, feito)) : item
  end

  def estado_de(numero, feito)
    return 'deixado' if deixadas.include?(numero)

    feito && feito['conferida'] ? GUARDADO : ABERTO
  end

  # O que falta na linha: do que sobrou do último conserto ou, sem conserto, dos motivos que a leitura gravou.
  def pendencia_de(linha, feito)
    motivos = feito ? [feito['sobrou']].compact : Array(linha.error_messages)
    Pendencia.new(motivos, celulas_de_agora(linha), com_nome: com_nome?).call
  end

  # O que cada tipo mostra além do comum: o valor que deu problema ou, no campo que a tela não conserta, o campo.
  def do_tipo(linha, pendencia)
    return { campo: pendencia.campo } if pendencia.campo

    tipo = pendencia.tipo
    item = { valor: valor(linha, alvo_do_valor(linha, tipo)) }
    item = item.merge(repetida(linha)) if tipo == 'duplicada'
    tipo == NOME ? item.merge(contato: contato(linha)) : item
  end

  # O que a pessoa guardou na linha: o valor como vai ser gravado, ou a linha com que ficou.
  def guardado(linha, feito)
    return { ficar_com: linha.row_number } if feito['campo'] == FICAR_COM

    { corrigido: CORRIGIDO.fetch(feito['campo']).filter_map { |coluna| feito['conferida'][coluna].presence }.first.to_s }
  end

  def alvo_do_valor(linha, tipo)
    tipo == 'duplicada' ? REPETIDA.values_at(*linha.error_messages).compact.first : ALVO_DO_TIPO[tipo]
  end

  # O valor que deu problema, como veio na planilha; sem o arquivo, a máscara que a linha guarda.
  def valor(linha, alvo)
    return '' unless alvo
    return celula(entradas[linha.row_number], alvo) if arquivo.existe?

    linha.public_send(MASCARAS.fetch(alvo)).to_s
  end

  # A linha sem nome mostra por onde a pessoa é achada: o telefone ou, sem ele, o e-mail, já com o que foi consertado.
  def contato(linha)
    CONTATOS.filter_map { |alvo| consertos.dig(linha.row_number, 'valores', alvo).presence || valor(linha, alvo).presence }.first.to_s
  end

  # As células da linha com o que a pessoa já consertou por cima. Sem o arquivo das linhas com problema, só o que a
  # linha no banco guarda inteiro: o nome e a empresa.
  def celulas_de_agora(linha)
    consertadas = consertos.dig(linha.row_number, 'valores').to_h
    ALVOS.index_with { |alvo| consertadas[alvo] || celula_inteira(linha, alvo) }
  end

  def celula_inteira(linha, alvo)
    return celula(entradas[linha.row_number], alvo) if arquivo.existe?

    NA_LINHA.key?(alvo) ? linha.public_send(NA_LINHA.fetch(alvo)).to_s : ''
  end

  # Sem coluna de nome na planilha, a linha sem nome não é problema.
  def com_nome?
    return @com_nome if defined?(@com_nome)

    @com_nome = !Relacionamentos::Trazer::Colunas.new(@importacao).alvos['name'].nil?
  end

  def celula(entrada, alvo)
    entrada.to_h.dig('celulas', alvo).to_s.strip
  end

  def repetida(linha)
    entrada = entradas[linha.row_number]
    outra = entrada && entrada['outra']
    { outraLinha: outra && outra['linha'], duplicadas: outra ? [outra, entrada].map { |uma| contatos_da_linha(uma) } : [] }
  end

  def contatos_da_linha(entrada)
    { linha: entrada['linha'], telefone: celula(entrada, 'phone'), email: celula(entrada, 'email') }
  end

  # { número da linha => o que o arquivo guarda dela }, das linhas desta página, numa leitura só do arquivo.
  def entradas
    @entradas ||= arquivo.ler(linhas.map(&:row_number))
  end

  # { número da linha => o que a pessoa consertou nela }, numa leitura só do arquivo dos consertos.
  def consertos
    @arquivo_dos_consertos.ler
  end

  def deixadas
    @deixadas ||= ContactImports::Trazer::Conferencia.new(@importacao).deixadas
  end

  attr_reader :arquivo
end

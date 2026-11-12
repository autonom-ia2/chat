# A leitura de uma planilha de "Trazer minha lista" (#2896), no formato que a tela lê.
#
# - Vencida (ContactImports::Trazer::Conferencia.vencida?): só `vencida`, em qualquer estado da leitura. Os arquivos da
#   conferência já sumiram e nada mais pode ser feito com ela.
# - Enquanto a planilha é lida em segundo plano: só `lendo`, sem abrir arquivo nenhum.
# - A leitura falhou: `falhou` com o motivo em palavras da tela (planilha vazia, sem contato, ou não deu para ler).
# - Pronta: as colunas e para onde vão, o resumo, os exemplos e as linhas que precisam da pessoa (uma página por vez).
#   O resumo é o da leitura e não muda com o que a pessoa conserta, menos `entram`: quantas pessoas entram se ela mandar
#   trazer agora, a mesma conta do "Trazer" (ContactImports::Trazer::QuemEntra). `juntadas` são as linhas que eram a
#   mesma pessoa de outra linha e viraram uma só (não entram no total). `perguntas` são as que a tela faz e `respostas`
#   o que a pessoa já respondeu (Relacionamentos::Trazer::Perguntas). `tem_empresa` diz se o destino "telefone da
#   empresa" pode ser oferecido (Relacionamentos::Trazer::Colunas#tem_empresa?).
# - `aviso` só existe quando há o que avisar: `mudanca_desfeita` depois que a mudança da pessoa fez a leitura falhar e
#   o servidor a desfez (ContactImports::Trazer::DesfazerMudanca). Some na próxima mudança que der certo.
#
# A troca de coluna que vale na hora responde com esta mesma leitura inteira.
#
# Cada arquivo da conferência é lido uma vez por resposta: o leitor dos consertos é criado aqui e passado adiante.
#
# O valor inteiro de telefone, e-mail e nome só existe nesta resposta: nada é gravado a mais.
class Relacionamentos::Trazer::Leitura
  POR_PAGINA = 200
  LENDO = %w[uploaded validating].freeze
  RASCUNHO = (LENDO + %w[validation_failed ready_to_confirm]).freeze
  # Na ordem em que valem: o primeiro motivo que a leitura gravou decide.
  ERROS = { 'empty_file' => 'vazia', 'missing_contact_column' => 'sem_contato', 'no_valid_rows' => 'sem_contato' }.freeze
  OUTRO_ERRO = 'leitura'.freeze

  # Página que não existe (texto, zero, negativa, além da última) vira a primeira ou a última que existe.
  def initialize(importacao, pagina: nil)
    @importacao = importacao
    @pagina = pagina.to_i.clamp(1, [(importacao.invalid_rows.to_f / POR_PAGINA).ceil, 1].max)
  end

  def call
    return { id: @importacao.id, situacao: 'vencida' } if ContactImports::Trazer::Conferencia.vencida?(@importacao)
    return { id: @importacao.id, situacao: 'lendo' } if LENDO.include?(@importacao.status)
    return { id: @importacao.id, situacao: 'falhou', erro: erro } if @importacao.validation_failed?

    pronta
  end

  private

  def erro
    motivos = @importacao.validation_summary.to_h['errors'].to_h.keys
    ERROS.find { |motivo, _erro| motivos.include?(motivo) }&.last || OUTRO_ERRO
  end

  def pronta
    consertos = ContactImports::Trazer::Consertos.new(@importacao)
    problemas = Relacionamentos::Trazer::Problemas.new(@importacao, pagina: @pagina, por_pagina: POR_PAGINA, consertos: consertos)
    das_colunas.merge(
      arquivo: @importacao.source_filename, valores: problemas.inteiros? ? 'inteiros' : 'mascarados', resumo: resumo(consertos.ler),
      exemplos: Relacionamentos::Trazer::Exemplos.new(@importacao).call, problemas: problemas.call,
      problemas_total: @importacao.invalid_rows, pagina: @pagina, por_pagina: POR_PAGINA
    ).merge(aviso)
  end

  def das_colunas
    perguntas = Relacionamentos::Trazer::Perguntas.new(@importacao)
    colunas = Relacionamentos::Trazer::Colunas.new(@importacao)
    { id: @importacao.id, situacao: 'pronta', colunas: colunas.call, tem_empresa: colunas.tem_empresa?, perguntas: perguntas.call,
      respostas: perguntas.respostas_da_tela }
  end

  def resumo(consertos)
    ja_existiam = @importacao.validation_summary.to_h['existing_contacts'].to_i
    entram = ContactImports::Trazer::QuemEntra.new(@importacao, consertos).quantas
    { total: @importacao.total_rows, novas: @importacao.valid_rows - ja_existiam, completadas: ja_existiam, comProblema: @importacao.invalid_rows,
      juntadas: @importacao.validation_summary.to_h['mesma_pessoa'].to_i, entram: entram }
  end

  # { aviso: 'mudanca_desfeita' }, ou nada.
  def aviso
    { aviso: ContactImports::Trazer::Conferencia.new(@importacao).aviso }.compact
  end
end

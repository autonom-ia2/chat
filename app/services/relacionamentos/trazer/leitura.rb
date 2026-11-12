# A leitura de uma planilha de "Trazer minha lista" (#2896), no formato que a tela lê.
#
# - Enquanto a planilha é lida em segundo plano: só `lendo`, sem abrir arquivo nenhum.
# - A leitura falhou: `falhou` com o motivo em palavras da tela (planilha vazia, sem contato, ou não deu para ler).
# - Pronta: as colunas e para onde vão, o resumo, os exemplos e as linhas que precisam da pessoa (uma página por vez).
#   O resumo é o da leitura e não muda com o que a pessoa conserta. `perguntas` e `respostas` chegam na Fatia 2.
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
    planilha = Relacionamentos::Trazer::LinhasDaPlanilha.new(@importacao)
    problemas = Relacionamentos::Trazer::Problemas.new(@importacao, planilha, pagina: @pagina, por_pagina: POR_PAGINA).call
    {
      id: @importacao.id, situacao: 'pronta', arquivo: @importacao.source_filename, valores: planilha.inteira? ? 'inteiros' : 'mascarados',
      colunas: Relacionamentos::Trazer::Colunas.new(@importacao).call, perguntas: [], respostas: {}, resumo: resumo,
      exemplos: planilha.exemplos, problemas: problemas, problemas_total: @importacao.invalid_rows, pagina: @pagina, por_pagina: POR_PAGINA
    }
  end

  def resumo
    ja_existiam = @importacao.validation_summary.to_h['existing_contacts'].to_i
    { total: @importacao.total_rows, novas: @importacao.valid_rows - ja_existiam, completadas: ja_existiam, comProblema: @importacao.invalid_rows }
  end
end

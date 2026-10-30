# Abas de lista da planilha do painel de desempenho (#2226): Procuras (uma linha por procura real, sem testes, com
# todos os nomes já traduzidos pelo catálogo) e Regras quebradas.
module Autonomia::Desempenho::Exportacao::Planilha::Listas
  COLUNAS_DO_INICIO = [%w[quando data_hora 17], %w[conversa inteiro 10], %w[procura inteiro 9], %w[tema texto 26]].freeze
  COLUNAS_DO_MEIO = [%w[marco texto 24], %w[marcos texto 44], %w[resultado texto 26], %w[grupo texto 14], %w[motivos texto 30],
                     %w[qualidade texto 14], %w[regras texto 30], %w[quem texto 18], %w[origem texto 18]].freeze
  COLUNAS_DO_FIM = [%w[compra texto 14], %w[perda texto 12], %w[precisava texto 12], %w[teve texto 12],
                    %w[resumo texto_longo 60]].freeze
  SIM_OU_NAO = { 'compra' => 'compra', 'perda' => 'perda_evitavel', 'precisava' => 'precisava_pessoa', 'teve' => 'teve_pessoa' }.freeze
  COLUNAS_DAS_REGRAS = [
    ['tabelas.regra', :texto, 28], ['planilha.descricao', :texto_longo, 44], ['tabelas.procuras', :inteiro, 11], ['%', :pct, 9],
    ['tabelas.quase_sempre', :texto, 13], ['planilha.exemplo_conversa', :texto, 22], ['planilha.exemplo_resumo', :texto_longo, 60]
  ].freeze

  # [{ id:, titulo:, tipo:, largura: }] da aba Procuras; os cortes entram um por coluna, na ordem do catálogo.
  def colunas_das_procuras
    cortes = catalogo['cortes'].to_h.keys.map { |corte| coluna(titulo_do_corte(corte), :texto, 18).merge(id: "corte:#{corte}") }
    anuncio = meta['anuncios_ligados'] ? [%w[anuncio texto 22]] : []
    [*colunas_de_procura(COLUNAS_DO_INICIO), *cortes, *colunas_de_procura(COLUNAS_DO_MEIO + anuncio + COLUNAS_DO_FIM)]
  end

  def procuras_reais
    Array(@painel['procuras']).reject { |procura| procura['teste'] }
  end

  def aba_procuras
    colunas = colunas_das_procuras
    ordenadas = procuras_reais.sort_by { |procura| [procura['inicio'].to_s, procura['procura'].to_i] }
    linhas = ordenadas.map { |procura| colunas.map { |item| valor_da_procura(item[:id], procura) } }
    nota = t('planilha.nota_grupo', compra: nomes['compra'].presence || t('planilha.procura.compra', nome: nome_do_agente))
    nova_aba(t('planilha.abas.procuras'), t('planilha.procuras_titulo'), nota: nota) { |sheet| tabela_de_dados(sheet, colunas, linhas) }
  end

  def aba_regras
    linhas = Array(@painel.dig('qualidade', 'regras')).map { |regra| linha_da_regra(regra) }
    nova_aba(t('planilha.abas.regras'), t('planilha.regras_titulo')) { |sheet| tabela_de_dados(sheet, colunas_de(COLUNAS_DAS_REGRAS), linhas) }
  end

  private

  # A coluna "compra" leva o nome do negócio (do contrato); as outras, o i18n.
  def colunas_de_procura(lista)
    lista.map do |id, tipo, largura|
      titulo = id == 'compra' ? nomes['compra'].presence || t('planilha.procura.compra') : t("planilha.procura.#{id}", nome: nome_do_agente)
      coluna(titulo, tipo.to_sym, largura.to_i).merge(id: id)
    end
  end

  def titulo_do_corte(corte)
    Array(@painel['cortes']).find { |item| item['id'] == corte }&.dig('nome') || t('sem_nome')
  end

  def linha_da_regra(regra)
    exemplo = Array(regra['exemplos']).first.to_h
    [regra['nome'], regra['descricao'], regra['procuras'].to_i, fracao(regra['pct']), sim_ou_nao(regra['sistemica']),
     exemplo.any? ? prova_curta(exemplo) : nil, exemplo['resumo']]
  end

  # Cada coluna tem o seu método `procura_<id>`; os cortes saem do catálogo.
  def valor_da_procura(id, procura)
    return nome_do_corte(catalogo, id.delete_prefix('corte:'), procura.dig('cortes', id.delete_prefix('corte:'))) if id.start_with?('corte:')
    return sim_ou_nao(procura[SIM_OU_NAO[id]]) if SIM_OU_NAO.key?(id)

    send("procura_#{id}", procura)
  end

  def sim_ou_nao(valor)
    valor ? t('sim') : t('nao')
  end

  def procura_quando(procura) = hora_de_parede(procura['inicio'])
  def procura_conversa(procura) = procura['conversa'].to_i
  def procura_procura(procura) = procura['procura'].to_i
  def procura_tema(procura) = nome_de(catalogo, 'temas', procura['tema_id'])
  def procura_quem(procura) = nome_de(catalogo, 'quem', procura['quem_id'])
  def procura_origem(procura) = nome_de(catalogo, 'origens', procura['origem_id'])
  def procura_resultado(procura) = nome_de(catalogo, 'resultados', procura['resultado_id'])
  def procura_resumo(procura) = procura['resumo'].to_s
  def procura_marcos(procura) = nomes_da_lista(procura['marcos'], 'marcos', ' · ')
  def procura_motivos(procura) = nomes_da_lista(procura['motivo_ids'], 'motivos', ', ')
  def procura_regras(procura) = nomes_da_lista(procura['regra_ids'], 'regras', ', ')
  def procura_qualidade(procura) = t("qualidade.#{procura['qualidade_id']}", default: '')

  def procura_grupo(procura)
    t("grupos.#{catalogo.dig('resultados', procura['resultado_id'].to_s, 'grupo')}", default: '')
  end

  # A etapa do funil mais avançada que a procura alcançou (a mesma regra do funil: os marcos da etapa).
  def procura_marco(procura)
    marcos = Array(procura['marcos'])
    Array(@painel.dig('funil', 'etapas')).reverse.find do |etapa|
      Autonomia::Desempenho::Conta.marcos_da_etapa(etapa).intersect?(marcos)
    end&.dig('nome')
  end

  def procura_anuncio(procura)
    return nil if procura['anuncio_id'].blank?

    Array(@painel.dig('origem', 'anuncios')).find { |anuncio| anuncio['id'] == procura['anuncio_id'] }&.dig('nome') || t('sem_nome')
  end

  def nomes_da_lista(ids, tipo, separador)
    Array(ids).map { |id| nome_de(catalogo, tipo, id) }.join(separador)
  end
end

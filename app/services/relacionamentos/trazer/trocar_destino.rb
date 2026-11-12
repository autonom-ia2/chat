# A pessoa trocou o destino de uma coluna na conferência de "Trazer minha lista" (#2896).
#
# - A coluna entra num dos quatro alvos (nome, telefone, e-mail, empresa) ou sai de um: a planilha é lida de novo com a
#   escolha (a mesma de "Importar contatos": CampaignImports::ColumnChoice e DraftChanges#choose_columns). Quem chama
#   põe a leitura na fila quando `revalida` vem verdadeiro. Tirar a última coluna de telefone ou e-mail é recusado.
# - A coluna que não é alvo vira "não guardar": vale na hora. O destino vai para `options['trazer']['destinos']` e o
#   valor dela sai de todas as linhas da importação (`extra_values`), numa atualização só.
# - A coluna volta de "não guardar" para "informação": o valor só existe no arquivo, então a planilha é lida de novo,
#   com as mesmas colunas de agora.
#
# Tudo sob a trava da importação. Devolve o código do erro, ou se a planilha vai ser lida de novo.
class Relacionamentos::Trazer::TrocarDestino
  Resultado = Struct.new(:erro, :revalida, keyword_init: true)
  ALVO_DO_DESTINO = Relacionamentos::Trazer::Colunas::ALVOS.invert.freeze
  NAO_GUARDAR = Relacionamentos::Trazer::Colunas::NAO_GUARDAR
  EXTRAS = [Relacionamentos::Trazer::Colunas::INFORMACAO, NAO_GUARDAR].freeze

  def initialize(importacao, indice:, destino:)
    @importacao = importacao
    @indice = Integer(indice.to_s, 10, exception: false)
    @destino = destino.to_s
  end

  def call
    @importacao.with_lock { trocar }
  end

  private

  def trocar
    erro = erro_do_pedido
    return Resultado.new(erro: erro) if erro
    return ler_de_novo(nova_escolha) if alvo_atual != alvo_novo
    return Resultado.new(revalida: false) if alvo_novo || colunas.destino_da_extra(@indice) == @destino

    @destino == NAO_GUARDAR ? deixar_de_guardar : ler_de_novo(colunas.alvos)
  end

  def erro_do_pedido
    return 'leitura_nao_pronta' unless @importacao.ready_to_confirm?
    return 'coluna_desconhecida' unless colunas.indices.include?(@indice)

    'destino_desconhecido' unless ALVO_DO_DESTINO.key?(@destino) || EXTRAS.include?(@destino)
  end

  def ler_de_novo(alvos)
    escolha = CampaignImports::ColumnChoice.new(alvos, column_count: colunas.total).mapping
    return Resultado.new(erro: 'sem_contato') unless escolha
    return Resultado.new(erro: 'leitura_nao_pronta') if CampaignImports::DraftChanges.new(@importacao).choose_columns(escolha)

    guardar_destino
    Resultado.new(revalida: true)
  end

  def deixar_de_guardar
    chave = colunas.chave_da_extra(@indice)
    guardar_destino
    # rubocop:disable Rails/SkipsModelValidations -- uma chave a menos em cada linha, de uma vez, sem carregar as linhas
    @importacao.campaign_import_rows.where('extra_values -> ? IS NOT NULL', chave).update_all(['extra_values = extra_values - ?::text', chave])
    # rubocop:enable Rails/SkipsModelValidations
    Resultado.new(revalida: false)
  end

  # A coluna deixa o alvo em que estava e, se o destino novo é um alvo, toma o lugar de quem estava nele.
  def nova_escolha
    sem_a_coluna = colunas.alvos.transform_values { |indice| indice == @indice ? nil : indice }
    alvo_novo ? sem_a_coluna.merge(alvo_novo => @indice) : sem_a_coluna
  end

  # "informação" é o padrão de toda coluna que não é alvo: só "não guardar" fica escrito.
  def guardar_destino
    opcoes = @importacao.options.to_h
    trazer = opcoes['trazer'].to_h
    destinos = trazer['destinos'].to_h.except(@indice.to_s)
    destinos = destinos.merge(@indice.to_s => @destino) if @destino == NAO_GUARDAR
    @importacao.update!(options: opcoes.merge('trazer' => trazer.merge('destinos' => destinos)))
  end

  def alvo_atual
    colunas.alvos.key(@indice)
  end

  def alvo_novo
    ALVO_DO_DESTINO[@destino]
  end

  def colunas
    @colunas ||= Relacionamentos::Trazer::Colunas.new(@importacao)
  end
end

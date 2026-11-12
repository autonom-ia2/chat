# A pessoa trocou o destino de uma coluna na conferência de "Trazer minha lista" (#2896).
#
# - A coluna entra num dos quatro alvos (nome, telefone, e-mail, empresa) ou sai de um: a planilha é lida de novo com a
#   escolha (a mesma de "Importar contatos": CampaignImports::ColumnChoice e DraftChanges#choose_columns). Quem chama
#   põe a leitura na fila quando `revalida` vem verdadeiro. Tirar a última coluna de telefone ou e-mail é recusado.
# - A coluna que não é alvo muda entre informação, cidade, telefone da empresa e cliente: vale na hora, só o destino
#   muda (`options['trazer']['destinos']`); o valor continua nas linhas e a gravação o leva para o lugar certo
#   (ContactImports::Trazer::DestinosDaLinha). A informação pode ganhar nome e "para que serve" (`campos`).
# - A coluna que não é alvo vira "não guardar": vale na hora, e o valor dela sai de todas as linhas da importação
#   (`extra_values`), numa atualização só.
# - A coluna volta de "não guardar" para outro destino: o valor só existe no arquivo, então a planilha é lida de novo,
#   com as mesmas colunas de agora.
#
# - O telefone da empresa só é aceito com coluna de empresa na planilha e Empresas ligada na conta (`sem_empresa`),
#   contando as colunas como ficariam DEPOIS da troca: a própria coluna de empresa não pode virar telefone da empresa.
#   A coluna de empresa deixou de ser empresa: a coluna que era telefone da empresa volta a ser informação.
# - O nome e o "para que serve" têm teto de tamanho (`valor_invalido`, motivo `muito_longo`) e nunca levam caractere
#   de controle (Relacionamentos::Trazer::Texto): quebra de linha e tabulação viram espaço, o resto sai.
#
# Antes de mandar ler a planilha de novo, a conferência como estava fica guardada (`anterior`): se a leitura nova
# falhar, o servidor desfaz a troca (ContactImports::Trazer::DesfazerMudanca). A troca que dá certo apaga o aviso de
# uma mudança desfeita antes.
#
# "Não guardar" apaga o valor de todas as linhas dentro do pedido, numa atualização só (até 50 mil linhas): fica assim
# por decisão do dono.
#
# A troca que lê a planilha de novo já deixa a importação `validating` na mesma trava em que grava a mudança
# (CampaignImports::DraftChanges#choose_columns): até a leitura nova terminar, a leitura velha não pode ser trazida. A
# conferência vencida recusa qualquer troca (`conferencia_vencida`).
#
# Tudo sob a trava da importação. Devolve o código do erro (e o motivo), ou se a planilha vai ser lida de novo.
class Relacionamentos::Trazer::TrocarDestino
  Resultado = Struct.new(:erro, :motivo, :revalida, keyword_init: true)
  ALVO_DO_DESTINO = Relacionamentos::Trazer::Colunas::ALVOS.invert.freeze
  INFORMACAO = Relacionamentos::Trazer::Colunas::INFORMACAO
  NAO_GUARDAR = Relacionamentos::Trazer::Colunas::NAO_GUARDAR
  TELEFONE_DA_EMPRESA = Relacionamentos::Trazer::Colunas::TELEFONE_DA_EMPRESA
  EXTRAS = Relacionamentos::Trazer::Colunas::EXTRAS
  # O nome vira o nome do atributo (texto curto); o "para que serve", a descrição dele.
  TETOS = { 'nome' => 255, 'para_que_serve' => 1000 }.freeze

  AVISO = ContactImports::Trazer::DesfazerMudanca::AVISO

  # campo: { 'nome' => 'Plano', 'para_que_serve' => '…' }, só para a coluna que é informação. anterior: a conferência
  # como estava no começo do pedido, quando quem chama já mexeu nela (Relacionamentos::Trazer::Responder).
  def initialize(importacao, indice:, destino:, campo: {}, anterior: nil)
    @importacao = importacao
    @anterior = anterior
    @indice = Integer(indice.to_s, 10, exception: false)
    @destino = destino.to_s
    @campo = campo.to_h.slice('nome', 'para_que_serve').transform_values { |texto| limpo(texto) }
  end

  def call
    @importacao.with_lock { trocar }
  end

  private

  # Os espaços são arrumados antes e depois: antes, para a quebra de linha virar espaço em vez de sumir.
  def limpo(texto)
    Relacionamentos::Trazer::Texto.sem_controle(texto.to_s.squish).squish
  end

  def trocar
    @anterior ||= ContactImports::Trazer::DesfazerMudanca.copia(@importacao)
    resultado = resultado_da_troca
    conferencia.tirar(AVISO) unless resultado.erro
    resultado
  end

  def resultado_da_troca
    erro = erro_do_pedido
    return Resultado.new(erro: erro) if erro
    return Resultado.new(erro: 'valor_invalido', motivo: 'muito_longo') if @campo.any? { |parte, texto| texto.length > TETOS.fetch(parte) }
    return ler_de_novo(nova_escolha) if alvo_atual != alvo_novo
    return Resultado.new(revalida: false) if alvo_novo

    trocar_extra(colunas.destino_da_extra(@indice))
  end

  def erro_do_pedido
    erro_da_importacao || erro_da_troca
  end

  def erro_da_importacao
    return ContactImports::Trazer::Conferencia::VENCIDA if ContactImports::Trazer::Conferencia.vencida?(@importacao)

    'leitura_nao_pronta' unless @importacao.ready_to_confirm?
  end

  def erro_da_troca
    return 'coluna_desconhecida' unless colunas.indices.include?(@indice)
    return 'destino_desconhecido' unless ALVO_DO_DESTINO.key?(@destino) || EXTRAS.include?(@destino)

    'sem_empresa' if @destino == TELEFONE_DA_EMPRESA && !colunas.tem_empresa?(nova_escolha)
  end

  def trocar_extra(atual)
    return deixar_de_guardar if @destino == NAO_GUARDAR && atual != NAO_GUARDAR
    return ler_de_novo(colunas.alvos) if atual == NAO_GUARDAR && @destino != NAO_GUARDAR

    guardar_destino
    Resultado.new(revalida: false)
  end

  def ler_de_novo(alvos)
    escolha = CampaignImports::ColumnChoice.new(alvos, column_count: colunas.total).mapping
    return Resultado.new(erro: 'sem_contato') unless escolha
    return Resultado.new(erro: 'leitura_nao_pronta') if CampaignImports::DraftChanges.new(@importacao).choose_columns(escolha)

    guardar_destino(com_empresa: escolha['company'].present?)
    conferencia.gravar(ContactImports::Trazer::DesfazerMudanca::CHAVE => @anterior)
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

  # "informação" é o padrão de toda coluna que não é alvo: só os outros destinos ficam escritos. O nome e o "para que
  # serve" só existem na coluna que é informação.
  def guardar_destino(com_empresa: true)
    chave = @indice.to_s
    destinos = conferencia.destinos.except(chave)
    destinos = destinos.reject { |_indice, destino| destino == TELEFONE_DA_EMPRESA } unless com_empresa
    destinos = destinos.merge(chave => @destino) if EXTRAS.include?(@destino) && @destino != INFORMACAO
    conferencia.gravar('destinos' => destinos, 'campos' => campos_com_o_da_coluna(chave))
  end

  def campos_com_o_da_coluna(chave)
    campos = conferencia.campos
    return campos.except(chave) unless @destino == INFORMACAO
    return campos if @campo.empty?

    campos.merge(chave => campos[chave].to_h.merge(@campo))
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

  # Lida de novo a cada uso: a troca muda as opções da importação.
  def conferencia
    ContactImports::Trazer::Conferencia.new(@importacao)
  end
end

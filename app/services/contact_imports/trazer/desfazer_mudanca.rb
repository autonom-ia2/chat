# "Trazer minha lista" (#2896): a mudança que faz a planilha ser lida de novo e termina em leitura que falha é desfeita
# aqui, uma vez só. Sem isso a pessoa ficaria presa numa lista que "falhou" por causa de uma troca de coluna.
#
# - Antes de cada troca de coluna ou resposta que lê a planilha de novo, quem muda guarda `copia`: a conferência como
#   estava (options['trazer']) e, das colunas, só o que diz para onde cada alvo aponta e se era duvidoso. São índices,
#   códigos e o nome que a pessoa deu a um campo: nunca o valor de uma célula. Fica em options['trazer']['anterior'].
# - A leitura que dá certo joga a cópia fora (ContactImports::Trazer::ConsertosDaLeitura#opcoes_depois_da_leitura).
# - A leitura que falha com a cópia guardada (ContactImports::Trazer::Validador) chama `call`: a conferência volta ao
#   que era, a cópia some, a planilha é lida de novo com as colunas de antes e a tela passa a mostrar o aviso
#   `mudanca_desfeita` até a próxima mudança que der certo. A importação nunca chega a ficar `validation_failed` no
#   caminho: a tela continua vendo "lendo".
# - Se a leitura refeita também falha, não há mais cópia: a importação fica como falhou, sem laço.
# - Só a leitura que ainda manda desfaz (o número dela, conferido sob a trava): a que perdeu a vez para outra não toca
#   em nada.
#
# A leitura refeita usa as colunas de antes como escolha (sem perguntar de novo a ninguém) e, quando termina, devolve às
# colunas o que elas diziam antes: o método da leitura, quais alvos eram duvidosos e a escolha manual que havia.
class ContactImports::Trazer::DesfazerMudanca
  CHAVE = 'anterior'.freeze
  AVISO = 'aviso'.freeze
  DESFEITA = 'mudanca_desfeita'.freeze
  MARCA = ContactImports::Trazer::Conferencia::CHAVE
  FORA_DA_COPIA = [CHAVE, AVISO, *ContactImports::Trazer::Validador::DA_LEITURA].freeze
  ALVOS = CampaignImports::SpreadsheetReader::TARGETS
  DO_ALVO = %w[column source confident confidence].freeze
  DA_RESOLUCAO = %w[method uncertain_targets manual_mapping].freeze
  ESCOLHA = 'manual_mapping'.freeze

  # O que guardar antes da mudança. Só índices e códigos.
  def self.copia(importacao)
    resolucao = importacao.schema_resolution.to_h
    alvos = resolucao['targets'].to_h.transform_values { |alvo| alvo.to_h.slice(*DO_ALVO) }
    { MARCA => importacao.options.to_h[MARCA].to_h.except(*FORA_DA_COPIA), 'resolucao' => resolucao.slice(*DA_RESOLUCAO).merge('targets' => alvos) }
  end

  def initialize(importacao)
    @importacao = importacao
  end

  def pendente?
    ContactImports::Trazer::Conferencia.new(@importacao).anterior.present?
  end

  # leitura: o número da leitura que falhou.
  def call(leitura)
    copia = voltar(leitura)
    return unless copia

    Rails.logger.warn("[ContactImports::Trazer::DesfazerMudanca] import_id=#{@importacao.id} undone")
    ContactImports::Trazer::Validador.new(@importacao).perform
    repor_as_colunas(copia['resolucao'].to_h)
  end

  private

  # A conferência de antes, já sem a cópia, e as colunas de antes como escolha da próxima leitura. Devolve a cópia, ou
  # nil quando esta leitura não manda mais.
  def voltar(leitura)
    @importacao.with_lock do
      conferencia = ContactImports::Trazer::Conferencia.new(@importacao)
      copia = conferencia.anterior
      next unless copia && @importacao.validating? && conferencia.leitura == leitura

      escolha = ALVOS.index_with { |alvo| copia.dig('resolucao', 'targets', alvo, 'column') }
      @importacao.update!(
        options: @importacao.options.to_h.merge(MARCA => copia[MARCA].to_h.merge(AVISO => DESFEITA)),
        schema_resolution: @importacao.schema_resolution.to_h.merge(ESCOLHA => escolha)
      )
      copia
    end
  end

  def repor_as_colunas(antes)
    @importacao.with_lock do
      next unless @importacao.ready_to_confirm?

      lida = @importacao.schema_resolution.to_h
      alvos = lida['targets'].to_h.merge(antes['targets'].to_h) { |_alvo, novo, antigo| novo.merge(antigo) }
      @importacao.update!(schema_resolution: lida.except(ESCOLHA).merge(antes.slice(*DA_RESOLUCAO).compact).merge('targets' => alvos))
    end
  end
end

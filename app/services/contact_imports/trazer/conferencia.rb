# O que a pessoa decidiu na conferência de "Trazer minha lista" (#2896), guardado em options['trazer'] da importação.
# Só índice de coluna, número de linha, código e o nome que a pessoa deu a um campo: nunca o valor de uma célula. O que
# ela consertou nas linhas tem arquivo próprio (ContactImports::Trazer::Consertos).
#
#   'destinos'  => { '4' => 'nao_guardar', '5' => 'cidade' }   coluna (índice) que não é "informação" => para onde vai
#   'campos'    => { '6' => { 'nome' => 'Plano', 'para_que_serve' => '…' } }   nome e descrição da informação
#   'respostas' => { 'clientes' => 'algumas', 'coluna_cliente' => 5, 'telefone' => 'da_empresa', 'coluna_telefone' => 2 }
#   'deixadas'  => [171]   linhas com problema que a pessoa deixou de fora
#   'anterior'  => {...}   a conferência como estava antes da mudança que leu a planilha de novo, enquanto a leitura não
#                          termina (ContactImports::Trazer::DesfazerMudanca)
#   'aviso'     => 'mudanca_desfeita'   o que a tela avisa até a próxima mudança que der certo
#   'fechamentos' => 2     quantas vezes o fechamento da conferência começou (ContactImports::Trazer::Fechamentos)
#   'leitura'   => 'f3b1…' o número da leitura que está rodando (ContactImports::Trazer::Validador); some quando ela termina
#   'leitura_em' => '2026-11-12T08:00:00Z'   quando essa leitura começou (só o instante); some junto com o número
#   'releituras' => 1      quantas vezes a varredura pôs a leitura parada de volta na fila
#
# `vencida?`: a importação com a marca que ainda não foi trazida e nasceu há mais tempo que o prazo da planilha original
# (CampaignImports::Config.original_file_retention). Os arquivos da conferência somem nesse prazo
# (ContactImports::Trazer::AnexosVencidos), mas o arquivo conferido vive mais: trazer depois disso gravaria a lista sem
# os consertos e com outra contagem. A vencida só pode ser vista como vencida; toda escrita é recusada.
class ContactImports::Trazer::Conferencia
  CHAVE = 'trazer'.freeze
  VENCIDA = 'conferencia_vencida'.freeze
  # Os estados em que a lista ainda não foi mandada trazer.
  POR_TRAZER = %w[uploaded validating needs_column_choice validation_failed ready_to_confirm].freeze

  def self.marcada?(importacao)
    importacao.options.to_h.key?(CHAVE)
  end

  def self.vencida?(importacao)
    return false unless marcada?(importacao) && importacao.created_at < CampaignImports::Config.original_file_retention.ago

    POR_TRAZER.include?(importacao.status) || ContactImports::Trazer::Fechamentos.desistiu?(importacao)
  end

  def initialize(importacao)
    @importacao = importacao
  end

  def destinos = estado['destinos'].to_h
  def campos = estado['campos'].to_h
  def respostas = estado['respostas'].to_h
  def deixadas = Array(estado['deixadas'])
  def anterior = estado['anterior']
  def aviso = estado['aviso']
  def fechamentos = estado['fechamentos'].to_i
  def leitura = estado['leitura']

  # O instante em que a leitura que está rodando começou, ou nil quando nenhuma começou.
  def leitura_em
    Time.zone.iso8601(estado['leitura_em'].to_s)
  rescue ArgumentError
    nil
  end

  def releituras = estado['releituras'].to_i

  # mudancas: { 'destinos' => {...}, 'respostas' => {...} }: cada chave troca a parte inteira. O que não mudou não é
  # escrito, e sem mudança nenhuma a importação não é tocada.
  def gravar(mudancas)
    novas = mudancas.stringify_keys.reject { |parte, valor| estado[parte] == valor || (valor.blank? && !estado.key?(parte)) }
    return if novas.empty?

    @importacao.update!(options: @importacao.options.to_h.merge(CHAVE => estado.merge(novas)))
  end

  # Tira partes inteiras ('aviso', 'anterior'). Sem nenhuma delas guardada, a importação não é tocada.
  def tirar(*partes)
    return unless partes.any? { |parte| estado.key?(parte) }

    @importacao.update!(options: @importacao.options.to_h.merge(CHAVE => estado.except(*partes)))
  end

  private

  def estado
    @importacao.options.to_h[CHAVE].to_h
  end
end

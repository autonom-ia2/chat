# Confere o estado final de uma conversa contra o esperado escrito ANTES de rodar (fixtures/conversas.json). Hard-assert:
# qualquer diferença é FALHA; erro de job, decisão de assunto que falhou ou avaliação que falhou (inclusive timeout)
# também são FALHA. Não existe "inconclusivo".
#
# A comparação de títulos é do teste (o nome que a IA deu ao card contém uma das palavras esperadas), não do produto.
class Stress::Conferencia
  IA_PADRAO = {
    'cards_abertos' => 'assunto', 'card_novo' => 'assunto', 'sem_card_novo' => 'assunto', 'novos_no_funil' => 'assunto',
    'nenhum_assunto_novo' => 'assunto',
    'foco' => 'assunto', 'etapa' => 'movimentacao', 'status' => 'movimentacao', 'atendente' => 'movimentacao',
    'retorno' => 'movimentacao', 'valor' => 'movimentacao', 'campo' => 'movimentacao'
  }.freeze

  def initialize(esperado:, resultado:, erros:)
    @esperado = Array(esperado)
    @final = resultado[:final]
    @turnos = resultado[:turnos]
    @erros = erros
  end

  def conferir
    checagens = @esperado.map { |item| checar(item) }
    checagens + automaticas
  end

  private

  def checar(item)
    tipo = item['tipo']
    ok, obtido = public_send("checar_#{tipo}", item)
    { tipo: tipo, ia: item['ia'] || IA_PADRAO.fetch(tipo), esperado: item.except('ia', 'por_que'), obtido: obtido, ok: ok }
  rescue KeyError, NoMethodError => e
    { tipo: tipo, ia: item['ia'] || 'assunto', esperado: item, obtido: "checagem inválida: #{e.message.first(80)}", ok: false }
  end

  def automaticas
    falhas_de_assunto = @turnos.flat_map { |t| t[:assunto] }.select { |d| d[:estado] == 'failed' }
    falhas_de_avaliacao = @turnos.flat_map { |t| t[:avaliacoes] }.select { |a| a[:status] == :failed }
    [
      { tipo: 'sem_erro_de_job', ia: 'sistema', esperado: 0, obtido: @erros, ok: @erros.empty? },
      { tipo: 'ia_de_assunto_respondeu', ia: 'assunto', esperado: 'nenhuma decisão failed',
        obtido: falhas_de_assunto.pluck(:motivo), ok: falhas_de_assunto.empty? },
      { tipo: 'ia_de_movimentacao_respondeu', ia: 'movimentacao', esperado: 'nenhuma avaliação failed',
        obtido: falhas_de_avaliacao.pluck(:erro), ok: falhas_de_avaliacao.empty? }
    ]
  end

  public

  def checar_cards_abertos(item)
    obtido = abertos.size
    [obtido == item['valor'], obtido]
  end

  def checar_card_novo(item)
    achados = novos.select { |c| c[:funil] == item['funil'] && c[:status] == 'open' && titulo_bate?(c, item) }
    [achados.any?, novos.map { |c| "#{c[:funil]}: #{c[:titulo]}" }]
  end

  def checar_sem_card_novo(_item)
    [novos.empty?, novos.map { |c| "#{c[:funil]}: #{c[:titulo]}" }]
  end

  # Nenhum card novo ganhou assunto (nome dado pela IA); o card que a caixa cria sozinho, sem nome, pode existir.
  def checar_nenhum_assunto_novo(_item)
    nomeados = novos.select { |c| c[:nomeado] }
    [nomeados.empty?, nomeados.map { |c| "#{c[:funil]}: #{c[:titulo]}" }]
  end

  def checar_novos_no_funil(item)
    obtido = novos.count { |c| c[:funil] == item['funil'] }
    [obtido == item['valor'], obtido]
  end

  def checar_foco(item)
    foco = @final[:foco]
    return [false, nil] if foco.nil?

    ok = item['ref'] ? foco[:ref] == item['ref'] : foco[:funil] == item['funil'] && titulo_bate?(foco, item)
    [ok, "#{foco[:ref]} #{foco[:funil]}: #{foco[:titulo]}"]
  end

  def checar_etapa(item)
    card = alvo(item)
    return [false, 'card não existe'] if card.nil?

    [Array(item['valor']).include?(card[:etapa]), card[:etapa]]
  end

  def checar_status(item)
    card = alvo(item)
    [card.present? && Array(item['valor']).include?(card[:status]), card&.dig(:status)]
  end

  def checar_atendente(item)
    obtido = @final[:atendente]
    ok = Array(item['valor']).include?(obtido[:estado]) && (item['pessoa'].nil? || item['pessoa'] == obtido[:pessoa])
    [ok, obtido]
  end

  def checar_retorno(item)
    card = alvo(item)
    tem = card.present? && card[:retornos].positive?
    [tem == item['valor'], card&.dig(:retornos)]
  end

  def checar_valor(item)
    card = alvo(item)
    return [false, 'card não existe'] if card.nil?

    valor = card[:valor_cents]
    ok = item.key?('cents') ? valor == item['cents'] : valor != item['nao']
    [ok, valor]
  end

  def checar_campo(item)
    valor = item['contato'] ? @final.dig(:contato_campos, item['chave']) : alvo(item)&.dig(:campos, item['chave'])
    [normal(valor).include?(normal(item['contem'])), valor]
  end

  private

  def abertos
    @final[:cards].select { |c| c[:status] == 'open' }
  end

  def novos
    @final[:cards].select { |c| c[:ref].to_s.start_with?('novo_') }
  end

  # O card de que a checagem fala: um card de antes (ref) ou o card novo do funil cujo título bate.
  def alvo(item)
    return @final[:cards].find { |c| c[:ref] == item['ref'] } if item['ref']

    novos.find { |c| c[:funil] == item['funil'] && titulo_bate?(c, item) }
  end

  def titulo_bate?(card, item)
    palavras = Array(item['titulo_tem'])
    palavras.empty? || palavras.any? { |palavra| normal(card[:titulo]).include?(normal(palavra)) }
  end

  def normal(texto)
    I18n.transliterate(texto.to_s.downcase)
  end
end

# O passo "ação" ao salvar (Autonomia::Automacao::Receita, que inclui este módulo): a ação está na lista permitida, o
# caminho tem todos os parâmetros, lê valores que a automação sabe ler e aponta para registros da conta (#2471), e o
# corpo fica no formato da ação e nas regras da lista (AcoesPermitidas). Saiu da Receita para ela caber no tamanho; usa
# os métodos dela (problemas_do_caminho, texto) e a conta (@conta).
module Autonomia::Automacao::AcaoNaReceita
  private

  def problemas_da_acao(passo)
    acao = passo['acao']
    return [texto(:acao_fora, passo: passo['id'], acao: acao)] unless ::Autonomia::Automacao::AcoesPermitidas.permitida?(acao)

    [*caminho_da_acao(passo), *corpo_da_acao(passo)]
  end

  def caminho_da_acao(passo)
    valores = passo['caminho'].to_h
    faltando = parametros(passo['acao']).reject { |nome| valores[nome].present? }
                                        .map { |nome| texto(:caminho_faltando, passo: passo['id'], campo: nome) }
    lidos = valores.values.filter_map { |valor| valor['$valor'] if valor.is_a?(Hash) }
    faltando + lidos.flat_map { |caminho| problemas_do_caminho(passo['id'], caminho, onde: :caminho) } + ids_de_fora(passo)
  end

  # #2471: o id escrito direto no caminho é de um registro desta conta (IdsDoCaminho).
  def ids_de_fora(passo)
    ::Autonomia::Automacao::IdsDoCaminho.de_fora(passo['acao'], passo['caminho'], @conta).map do |lista, id|
      texto(:id_de_fora, passo: passo['id'], recurso: I18n.t("autonomia.automacao.receita.recurso.#{lista}"), id: id)
    end
  end

  # O formato confere o corpo com um exemplo no lugar de cada valor calculado (Corpo.exemplo): chave fora do formato e
  # opção fora da lista continuam pegas. O valor de verdade é conferido de novo ao executar.
  def corpo_da_acao(passo)
    corpo = passo['corpo'].to_h
    exemplo = ::Autonomia::Automacao::Corpo.exemplo(passo['acao'], corpo)
    conferencia = ::Autonomia::Guide::Formatos::Conferencia.new(passo['acao'], exemplo, conta: @conta)
    calculo = ::Autonomia::Automacao::ProblemasDoCorpo.new(passo, conta: @conta) { |lido| problemas_do_caminho(passo['id'], lido, onde: :corpo) }
    calculo.problemas +
      conferencia.problemas_em_texto.map { |problema| texto(:corpo, passo: passo['id'], problema: problema) } +
      regras_da_lista(passo['id'], passo['acao'], conferencia.valores)
  end

  def regras_da_lista(id, acao, valores)
    ::Autonomia::Automacao::AcoesPermitidas.fora_da_lista(acao, valores).map { |chave, dados| texto(chave, passo: id, **dados) }
  end

  def parametros(acao)
    acao.split(' ', 2).last.split('/').filter_map { |segmento| segmento.delete_prefix(':') if segmento.start_with?(':') }
  end
end

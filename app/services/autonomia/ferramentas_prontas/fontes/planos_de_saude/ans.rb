# As operadoras da ANS na base baixada (#2858, F5). Pelo CNPJ ou pelo registro: as linhas dele (a ativa antes da
# cancelada). Pelo nome: todas as palavras no nome (razão social e fantasia, sem acento e sem caixa), no máximo `MAXIMO`.
class Autonomia::FerramentasProntas::Fontes::PlanosDeSaude::Ans < Autonomia::FerramentasProntas::Bases::Provedor
  NOME = 'ans'.freeze
  BASE = 'planos_de_saude'.freeze
  MAXIMO = 10

  def consultar(_consulta, params)
    exigir_base!
    com_data(listar(escopo(params).order(ativa: :desc, razao_social: :asc), 'operadoras', MAXIMO) { |item| operadora(item) })
  end

  private

  def escopo(params)
    base = Autonomia::FerramentasProntas::Bases::Operadora.vigente
    return base.where(cnpj: params['cnpj']) if params['cnpj']
    return base.where(registro_ans: params['registro_ans']) if params['registro_ans']

    Autonomia::FerramentasProntas::Lista.comparavel(params['nome']).split.inject(base) do |escopo, palavra|
      escopo.where('nome_busca LIKE ?', like(palavra))
    end
  end

  def operadora(item)
    {
      'razao_social' => item.razao_social, 'nome_fantasia' => item.nome_fantasia, 'registro_ans' => item.registro_ans,
      'cnpj' => item.cnpj, 'situacao' => item.ativa ? 'ativa' : 'cancelada', 'modalidade' => item.modalidade,
      'cidade' => item.cidade, 'uf' => item.uf, 'registrada_em' => item.registrada_em&.iso8601,
      'cancelada_em' => item.cancelada_em&.iso8601, 'motivo_do_cancelamento' => item.motivo_do_cancelamento
    }.compact
  end
end

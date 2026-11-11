# O PROVEDOR DE UMA BASE BAIXADA (#2858, F5): local (`HOST = nil`), sem rede, sem teto e sem cache. A busca é no banco,
# na geração que vale (`Vigente`), e a resposta leva `atualizado_em` (o dia em que a cópia entrou), para o agente dizer
# de quando é o dado. Base que nunca foi baixada (ou o banco fora): falha da fonte (`base_vazia`), e o agente ouve "não
# consegui consultar". Cada subclasse define `NOME` e `BASE` (a chave do `Estado`).
class Autonomia::FerramentasProntas::Bases::Provedor < Autonomia::FerramentasProntas::Provedor
  HOST = nil

  private

  def atualizado_em
    estados = Autonomia::FerramentasProntas::Bases::Estado
    @atualizado_em ||= estados.where(base: self.class::BASE).where.not(geracao_ativa: nil).pick(:atualizado_em)
  end

  # Confere que a base existe antes de buscar: sem ela, "não tem" seria mentira.
  def exigir_base!
    raise Falha, 'base_vazia' if atualizado_em.nil?
  end

  def com_data(dados)
    dados.merge('atualizado_em' => atualizado_em.to_date.iso8601)
  end

  # A busca que pode achar muitas: no máximo `maximo` linhas lidas (+1, para saber se passou), e a contagem só quando
  # passou. -> { 'total', 'mostrando'?, chave => itens }, ou NaoEncontrado.
  def listar(escopo, chave, maximo, &)
    linhas = escopo.limit(maximo + 1).to_a
    raise NaoEncontrado if linhas.empty?

    total = linhas.size > maximo ? escopo.unscope(:order, :limit).count : linhas.size
    itens = linhas.first(maximo).map(&)
    { 'total' => total }.merge(total > maximo ? { 'mostrando' => maximo } : {}).merge(chave => itens)
  end

  def like(palavra)
    "%#{ActiveRecord::Base.sanitize_sql_like(palavra)}%"
  end
end

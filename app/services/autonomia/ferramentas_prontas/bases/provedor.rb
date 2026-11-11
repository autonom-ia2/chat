# O PROVEDOR DE UMA BASE BAIXADA (#2858, F5): local (`HOST = nil`), sem rede, sem teto e sem cache. A busca é no banco,
# na geração que vale, e a resposta leva `atualizado_em` (o dia em que a cópia entrou), para o agente dizer de quando é
# o dado. Base que nunca foi baixada (ou o banco fora): falha da fonte (`base_vazia`), e o agente ouve "não consegui
# consultar". Cada subclasse define `NOME`, `BASE` (a chave do `Estado`) e `buscar(consulta, params)`.
#
# UMA GERAÇÃO POR CONSULTA: a busca faz mais de um comando (a soma e as contagens, a lista e o total). A geração que
# vale e o `atualizado_em` são lidos UMA vez, juntos, e todo comando filtra por ela (`da_base`). No fim, a geração é
# conferida: se a importação trocou (e começou a apagar a antiga) no meio, a busca refaz na nova, uma vez. Assim a
# resposta nunca mistura duas gerações nem sai vazia por causa da troca.
class Autonomia::FerramentasProntas::Bases::Provedor < Autonomia::FerramentasProntas::Provedor
  HOST = nil
  TENTATIVAS = 2

  def consultar(consulta, params)
    TENTATIVAS.times do
      @vigente = nil
      exigir_base!
      resposta = nao_encontrado_como_resposta { buscar(consulta, params) }
      next unless mesma_geracao?
      raise resposta if resposta.is_a?(NaoEncontrado)

      return resposta
    end
    raise Falha, 'base_em_troca'
  end

  private

  def nao_encontrado_como_resposta
    yield
  rescue NaoEncontrado => e
    e
  end

  # [geração que vale, atualizado_em], lidos juntos, uma vez por tentativa.
  def vigente
    @vigente ||= estados.where.not(geracao_ativa: nil).pick(:geracao_ativa, :atualizado_em)
  end

  def estados
    Autonomia::FerramentasProntas::Bases::Estado.where(base: self.class::BASE)
  end

  def mesma_geracao?
    estados.pick(:geracao_ativa) == vigente.first
  end

  def atualizado_em
    vigente&.last
  end

  # A tabela da base, só na geração lida no começo da consulta.
  def da_base(modelo)
    modelo.where(geracao: vigente.first)
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

  # O CNPJ guardado só com os dígitos sai com a máscara, pelo mesmo `Fontes::Cnpj.formatado` do card Dados da empresa.
  # O que não confere como CNPJ sai como veio.
  def cnpj_formatado(valor)
    cnpj = Autonomia::FerramentasProntas::Parametro.cnpj(valor)
    cnpj ? Autonomia::FerramentasProntas::Fontes::Cnpj.formatado(cnpj) : valor
  end

  def like(palavra)
    "%#{ActiveRecord::Base.sanitize_sql_like(palavra)}%"
  end
end

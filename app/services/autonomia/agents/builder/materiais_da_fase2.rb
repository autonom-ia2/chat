# #1426 (tema 4) — o que conta como base no status dos materiais que o Construtor vê, no piloto (Fase 2). Incluído no
# Builder; fora do piloto tudo continua como antes (todo material de conhecimento conta).
#
# - Material que não deu para ler (failed) não é base.
# - A foto mandada NA CRIAÇÃO (origem foto_da_criacao) que a revisão reprovou ou que não deu para ler já chegou ao
#   Construtor na conversa: não fica "aguardando", não segura o fechamento e também não conta como base. Se for o único
#   material, o Construtor pergunta se pode criar sem base, como sem material nenhum.
# - A foto mandada pela gaveta "O que sabe" é um material como os outros: reprovada, segura o fechamento.
module Autonomia::Agents::Builder::MateriaisDaFase2
  private

  def fase2_da_conta?
    Autonomia::Agents::Fase2.ligada?(@account)
  end

  def conta_como_base?(source)
    return true unless fase2_da_conta?

    !source.failed? && !foto_da_criacao_fora?(source)
  end

  def foto_da_criacao_fora?(source)
    source.source_type == Autonomia::Agents::Source::FOTO &&
      source.origem == Autonomia::Agents::Source::ORIGEM_FOTO_DA_CRIACAO &&
      (source.failed? || source.review_status == 'needs_resend')
  end
end

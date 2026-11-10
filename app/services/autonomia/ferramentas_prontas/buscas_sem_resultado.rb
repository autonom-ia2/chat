# AS BUSCAS SEM RESULTADO DA VITRINE (#2858, F2): o que as pessoas procuram e o catálogo ainda não tem ("passagem de
# avião"), para a equipe decidir a próxima fonte. Contadas por conta, no Redis, com validade de 90 dias: não é registro
# de negócio, é sinal de produto, e fica fora do banco (sem migration). O termo vai em minúsculas, sem espaço sobrando
# e cortado em `MAX_TERMO`; no máximo `MAX_TERMOS` diferentes por conta (os de menor contagem saem antes de o novo
# entrar, para o novo não ser o cortado). Termo com `MAX_DIGITOS` dígitos ou mais não é guardado: pode ser um CPF, um
# CEP ou um telefone digitado na busca, e não é sinal de produto.
#
# Leitura: `BuscasSemResultado.da_conta(account)` -> [[termo, vezes], ...], do mais buscado para o menos.
module Autonomia::FerramentasProntas::BuscasSemResultado
  CHAVE = 'autonomia:prontas:buscas_sem_resultado'.freeze
  VALIDADE = 90.days.to_i
  MAX_TERMO = 60
  MAX_TERMOS = 200
  MAX_DIGITOS = 5
  ERROS_DO_REDIS = Autonomia::FerramentasProntas::TetoDoProvedor::ERROS_DO_REDIS

  module_function

  def registrar(account, termo)
    texto = termo.to_s.squish.downcase.first(MAX_TERMO)
    return if texto.blank? || texto.count('0-9') >= MAX_DIGITOS

    Redis::Alfred.with do |conn|
      conn.multi do |fila|
        fila.zremrangebyrank(chave(account), 0, -MAX_TERMOS)
        fila.zincrby(chave(account), 1, texto)
        fila.expire(chave(account), VALIDADE)
      end
    end
  rescue *ERROS_DO_REDIS => e
    Rails.logger.warn("[autonomia][vitrine] busca sem resultado não registrada conta=#{account.id} #{e.class}")
  end

  def da_conta(account, limite: 50)
    Redis::Alfred.with { |conn| conn.zrevrange(chave(account), 0, limite - 1, with_scores: true) }
                 .map { |texto, vezes| [texto, vezes.to_i] }
  end

  def chave(account)
    "#{CHAVE}:#{account.id}"
  end
end

# Ponto de encaixe das metas por pessoa na visão "Equipe" de CRM › Números (#1992, F5 do #1871). As metas por pessoa
# são da F4 (#1991, flag `crm_metas`), feita em paralelo. Até ela entrar, ninguém tem meta: as linhas de "Quem cuidou"
# saem sem barra e o "No caminho certo" não aparece.
#
# Como as duas fases se juntam: o PR que entrar por último troca `por_pessoa` pela leitura das metas da F4 — com a flag
# `crm_metas` ligada, a soma das metas do mês de cada pessoa nos funis de Vender listados, em centavos da moeda pedida.
# Nada mais muda: a visão "Equipe" e a tela já tratam a meta, a barra e o "No caminho certo".
class Crm::Numeros::MetasDaEquipe
  def initialize(account:, mes:, pipeline_ids:, moeda:)
    @account = account
    @mes = mes
    @pipeline_ids = pipeline_ids
    @moeda = moeda
  end

  # { user_id => cents }
  def por_pessoa
    {}
  end
end

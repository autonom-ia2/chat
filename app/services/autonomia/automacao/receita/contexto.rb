# O que os validadores da Receita recebem (#2608): o conteúdo da receita, a conta, quem salva (`account_user`, nil no
# catálogo e na leitura sem pessoa), o tipo do registro em que ela roda (`alvo`, Receita#alvo) e, no ramo do "em outro
# registro", o tipo do alvo do gatilho da mãe (`origem`, G65).
Autonomia::Automacao::Receita::Contexto = Data.define(:receita, :conta, :account_user, :alvo, :origem)

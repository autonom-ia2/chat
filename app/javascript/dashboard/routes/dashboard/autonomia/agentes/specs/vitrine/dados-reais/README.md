# Dados reais das ferramentas prontas (#2858)

O `dados` que o agente recebe de cada fonte grátis no ar (F1 a F4), usado por `../resultadoDasFontes.spec.js`.

Como foi feito, em 11/11/2026: uma chamada real por consulta, pelo próprio adaptador do servidor (os provedores de
`app/services/autonomia/ferramentas_prontas/fontes`, depois o `refinar` da consulta e o `Resposta.enxugar`), sem cache.
Cada arquivo guarda, por consulta, o provedor que respondeu e o `dados`. Sem IA e sem fonte paga.

O script está versionado: `script/ferramentas_prontas/gravar_dados_reais.rb`, que roda `dados_reais.rb` ao lado (os
pedidos ficam no `CASOS`, a anonimização no `ANONIMIZACAO`). Ele desliga o cache (`Rails.cache` vira NullStore), não usa
conta nem contador e só roda no ambiente de teste. Cada fonte está no `ANONIMIZACAO`, como `:sem_pessoa_fisica` (com o
motivo) ou com o anonimizador dela; fonte fora da lista aborta antes de qualquer chamada. Para gravar de novo:

```sh
RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais.rb            # todas
RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais.rb ncm chuva  # só essas
RAILS_ENV=test bundle exec rails runner script/ferramentas_prontas/gravar_dados_reais.rb banco_central.focus  # uma consulta
pnpm exec prettier --write app/javascript/dashboard/routes/dashboard/autonomia/agentes/specs/vitrine/dados-reais/*.json
```

Fonte nova: ponha os pedidos dela no `CASOS` e a decisão dela no `ANONIMIZACAO`, rode só ela, confira o arquivo e ponha
no spec uma asserção do essencial. O spec falha enquanto uma fonte do
catálogo da vitrine não tiver arquivo aqui.

Fonte paga (a BigDataCorp, na F7): não se chama a fonte para gravar a fixture. O arquivo é feito à mão a partir da
resposta documentada pelo fornecedor, passado pelo adaptador do servidor num spec, com dados fictícios, e leva no topo
a marca `"_origem": "feito à mão a partir da documentação do fornecedor, sem chamada real"`.

`ncm.json` e `compras_governo.json` foram gravados de novo no mesmo dia, pelo script, depois de duas mudanças no
adaptador: a ordem da NCM (o código de 8 dígitos antes do de 4) e a compra de valor sigiloso sem o campo de valor.

| Arquivo | Consulta e pedido | Provedor que respondeu |
|---|---|---|
| cep.json | endereco: 01001-000 | BrasilAPI |
| cnpj.json | empresa: consultado com o CNPJ da Petrobras, gravado anonimizado | BrasilAPI |
| cpf.json | conferir: 111.444.777-35 (número de exemplo; conta local, sem rede) | cálculo local |
| fipe.json | marcas e modelos (carros, GM, "onix"); preco 004517-9 2020 | BrasilAPI; Parallelum (a BrasilAPI deu erro no preço) |
| feriados.json | feriados de 2026; dias úteis até 30/11/2026 | BrasilAPI |
| banco_central.json | selic, ipca, dolar, focus (ipca) | SGS, PTAX e Focus do Banco Central |
| cidades.json | estados; cidades do AC | IBGE |
| ddd.json | ddd 34 | BrasilAPI |
| localizacao.json | cidade de -18.9186, -48.2772 | sedes (tabela local; o Photon não conferiu o município) |
| bancos.json | banco 341 | BrasilAPI |
| hospitais.json | Campinas SP, hospital | CNES (Ministério da Saúde) |
| procedimentos.json | codigo 10101012; busca "hemograma" | TUSS (tabela no repositório) |
| doencas.json | codigo J45; busca "asma" | CID-10 (tabela no repositório) |
| ncm.json | buscar "parafuso"; codigo 7318.15.00 | BrasilAPI |
| compras_governo.json | Uberlândia MG, últimos 7 dias, pregão eletrônico | PNCP (órgãos públicos) |
| estacoes.json | Uberlândia MG | INMET |
| chuva.json | Uberlândia MG, 04 a 10/11/2026 | Open-Meteo |
| produtos_seguradoras.json | seguradoras "Allianz"; produtos Allianz, riscos cibernéticos | Open Insurance Brasil |
| corretor_susep.json | por_nome "corretora de seguros", pessoa jurídica | SUSEP |

Anonimizado pelo script:
- `corretor_susep.json`: o nome e o registro de cada corretor viram "CORRETORA EXEMPLO N LTDA" e um número fictício
  (situação e ramos são os reais);
- `cnpj.json`: número, razão social e nome fantasia de exemplo (11.222.333/0001-81, "EMPRESA EXEMPLO LTDA"). O CNPJ do
  MEI traz o nome da pessoa na razão social, e a fonte não diz de antemão se é MEI: todo CNPJ gravado sai assim.

O resto é dado público de órgão, empresa pública, seguradora ou tabela oficial; nenhum CPF real e nenhum nome de pessoa
física.

`banco_central.json` (focus) foi gravado de novo em 11/11/2026, pelo script, depois que a mediana do Focus passou a vir
com a unidade em `unidades`.

`chuva.json` foi gravado de novo em 11/11/2026, pelo script, com 7 dias (04 a 10/11/2026): a lista de itens sem nome,
identificados pela data, passa pelo spec de cobertura.

# Dados reais das ferramentas prontas (#2858)

O `dados` que o agente recebe de cada fonte grátis no ar (F1 a F4), usado por `../resultadoDasFontes.spec.js`.

Como foi feito, em 11/11/2026: uma chamada real por consulta, pelo próprio adaptador do servidor (os provedores de
`app/services/autonomia/ferramentas_prontas/fontes`, depois o `refinar` da consulta e o `Resposta.enxugar`), sem cache.
Cada arquivo guarda, por consulta, o provedor que respondeu e o `dados`. Sem IA e sem fonte paga.

| Arquivo | Consulta e pedido | Provedor que respondeu |
|---|---|---|
| cep.json | endereco: 01001-000 | BrasilAPI |
| cnpj.json | empresa: Petrobras (sociedade de economia mista, dado público) | BrasilAPI |
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
| chuva.json | Uberlândia MG, 10/11/2026 | Open-Meteo |
| produtos_seguradoras.json | seguradoras "Allianz"; produtos Allianz, riscos cibernéticos | Open Insurance Brasil |
| corretor_susep.json | por_nome "corretora de seguros", pessoa jurídica | SUSEP |

Anonimizado: no `corretor_susep.json`, o nome e o registro de cada corretora foram trocados por "CORRETORA EXEMPLO N
LTDA" e um número fictício (situação e ramos são os reais). O resto é dado público de órgão, empresa pública,
seguradora ou tabela oficial; nenhum CPF real e nenhum nome de pessoa física.

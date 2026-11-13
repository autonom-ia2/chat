# Agentes prontos por ramo de seguro: pesquisa e fontes (#2881)

Este documento registra a pesquisa que deu origem aos modelos prontos de **seguro garantia** e de **transporte de
carga** (`config/agentes_por_pacote/seguros/modelos/`). Data da pesquisa: 10/11/2026.

- Só fontes públicas. Nenhum dado de cliente.
- Nenhuma chamada de IA paga. A única chamada feita foi à API aberta do Open Insurance (fase 1, sem chave), quatro
  pedidos em 10/11/2026.
- Cada fato traz a fonte entre colchetes. A lista de fontes está no fim, com a URL de cada uma.
- Quando o fato veio de matéria ou de corretora, e não da norma, a linha diz "segundo".

O que este documento **não** cobre:

- **Seguro auto.** O modelo `seguro_auto` entrou no piloto depois desta pesquisa e não tem levantamento de norma aqui.
- **O texto dos roteiros.** O que o agente fala está nos arquivos do modelo, não neste documento. Os três roteiros
  pedem a leitura de quem conhece cada ramo antes de a flag `agente_modelos_seguro` ser ligada em qualquer conta.
- **Preço.** Nenhuma fonte pública traz preço, e o agente não cota: ele explica, colhe os dados e passa para a equipe.

Regra que saiu da pesquisa e vale nos roteiros: o agente não afirma o que a norma não diz. Lista de documentos é
sempre "costuma ser pedido; a seguradora confirma". O agente não diz se um juiz ou um órgão vai aceitar a apólice.

---

## Parte A: o que as normas dizem

### A1. Seguro garantia: Circular SUSEP 662/2022 [F1]

O texto foi lido inteiro, nas 7 páginas, a partir do PDF público.

| Tema | O que diz | Artigo |
|---|---|---|
| Quem é quem | **Tomador** é quem deve a obrigação (a empresa que contrata). **Segurado** é o credor: o órgão, a empresa ou o processo que exige a garantia. | art. 2º, IV e IX |
| Para que serve | Garante o cumprimento da obrigação. Se o tomador não cumprir, a seguradora indeniza. | arts. 2º, V, e 3º |
| Público e privado | Setor público é quando o contrato segue o direito público. Setor privado é quando segue o direito privado. | art. 2º, VI e VII |
| Processo judicial | O juízo pode agir em nome do segurado. | art. 2º, § 2º |
| Valor da garantia | Quem define é o segurado, conforme a obrigação. | art. 6º |
| Vigência | Igual ao prazo da obrigação garantida. Se a apólice for mais curta, a cobertura continua enquanto houver risco. | arts. 7º e 8º |
| Aviso de fim | A seguradora avisa segurado e tomador pelo menos 90 dias antes do fim da vigência. | art. 9º, III |
| Mudar a apólice | Só com pedido ou concordância do segurado. | art. 10 |
| Rateio | A contratação é a "risco absoluto": não existe rateio. | art. 13 |
| Prêmio | Quem paga é o tomador. **A apólice continua valendo mesmo com o prêmio atrasado.** | art. 16, § 1º |
| Sinistro | É a inadimplência do tomador. Quem comprova é o segurado, pelas regras do contrato. | arts. 2º, VIII, e 18 |
| Indenização | A seguradora paga em dinheiro ou termina a obrigação. | art. 21 |
| Duas apólices | Não pode haver duas apólices para a mesma obrigação, salvo a complementar. | art. 23 |
| Quando termina | Obrigação concluída e aceita, acordo, valor esgotado, contrato extinto ou fim da vigência. | art. 26 |
| Análise | A seguradora avalia o tomador e o contrato. | art. 28 |
| Contragarantia | É um contrato à parte, entre seguradora e tomador. Não afeta o segurado e fica fora da SUSEP. | art. 32 |
| Grandes riscos | Valem só os arts. 2º e 3º. O resto é facultativo. | art. 34, parágrafo único |

Fatos de contexto:
- A circular entrou em vigor em 02/05/2022 (art. 38).
- Ela revogou as Circulares 477/2013 e 577/2018 (art. 37).
- Desde 01/01/2023, só se vende plano adaptado a ela (art. 35).

A circular **não lista as modalidades**. Cada seguradora escreve o clausulado de cada uma (art. 27, parágrafo único).
Os nomes abaixo vêm dos clausulados públicos.

### A2. Modalidades publicadas pelas seguradoras

**Setor público.** Fonte: condições da MSIG, junho/2025, ramo 0775 [F4].

| Modalidade | Objetivo |
|---|---|
| I. Licitante | Paga a multa se a empresa vencer a licitação e se recusar a assinar o contrato. A vigência vai até o prazo de assinatura do edital. |
| II. Construção, fornecimento ou prestação de serviços | Garante a execução do contrato. Muitos editais a chamam de "executante construtor, fornecedor ou prestador" [F5]. |
| III. Retenção de pagamentos | Substitui o dinheiro que o órgão reteria. |
| IV. Adiantamento de pagamentos | Garante o dinheiro adiantado pelo órgão. |
| V. Manutenção corretiva | Garante o conserto depois da entrega. |
| VI. Judicial fiscal | Garantia em processo fiscal. |
| VII. Judicial cível | Garantia em processo cível. |
| VIII. Judicial para execução fiscal | Garantia na execução fiscal. |
| IX. Aduaneiro | Garante o termo de responsabilidade do Decreto 6.759/2009. O segurado é a União, pela Receita Federal. |
| X. Compra de energia elétrica | Garante a compra de energia. |
| XI. Processos administrativos | Garantia em processo administrativo. |
| XII. Judicial: execução trabalhista | Garantia na execução trabalhista. |
| XIII. Judicial: depósito recursal | Substitui o depósito recursal. |
| Adicional | Ações trabalhistas e previdenciárias. |

**Setor privado.** Fonte: condições da Essor, dezembro/2023 [F6].
- Adiantamento de pagamentos.
- Construção, fornecimento ou prestação de serviços.
- Retenção de pagamentos.
- Manutenção corretiva.
- Garantia de pagamentos.
- **Imobiliário.**
- Compra e venda de energia.
- Adicionais: ações trabalhistas e previdenciárias; multas aplicadas pelo segurado ao tomador.

**Open Insurance** (API aberta, 10/11/2026) [F12]:
- A Chubb publica produtos separados para o setor público. Exemplos: aduaneiro; manutenção corretiva; retenção; adiantamento; construção, fornecimento ou serviço; judicial; judicial para execução fiscal; judicial para depósito recursal; judicial para execução trabalhista; concessões; financeira; administrativo de créditos tributários.
- A Mapfre publica um produto só, "Garantia Segurado Setor Público". Ele traz as coberturas licitante, fornecimento, prestação de serviços, adiantamento, manutenção corretiva, judicial, judicial para execução fiscal, parcelamento administrativo, administrativo de créditos tributários e ações trabalhistas e previdenciárias.
- No diretório oficial, 20 entradas publicam garantia pública, 20 publicam garantia privada e 20 publicam transporte. Uma seguradora pode ter mais de uma entrada (v1 e v2).
- Entre as seguradoras estão BTG, Chubb, HDI, Itaú, Mapfre, Porto, Safra, Sompo e Swiss Re.
- **Nenhum produto publica preço.** A Sompo publica "não se aplica" nos requisitos mínimos.

### A3. Lei 14.133/2021: garantia em licitação e contrato público [F2]

- **Garantia de proposta (licitante):** até 1% do valor estimado (art. 58).
- **Quem escolhe a forma:** o contratado. Pode ser caução, seguro garantia, fiança bancária ou título de capitalização (art. 96).
- **Prazo para entregar o seguro garantia:** o edital dá pelo menos 1 mês, contado da homologação e antes da assinatura (art. 96).
- **Prêmio em atraso:** o seguro continua valendo. A vigência é igual ou maior que a do contrato e acompanha as mudanças por endosso (art. 97).
- **Percentual:** até 5% do valor inicial, ou até 10% com justificativa (art. 98).
- **Obra ou serviço de engenharia de grande vulto:** até 30%, com cláusula de retomada (art. 99).
- **Retomada:** a seguradora assume a obra ou paga a importância segurada (art. 102).

### A4. Garantia na Justiça [F3a, F3b]

- **CPC, art. 835, § 2º:** o seguro garantia judicial vale como dinheiro para substituir a penhora. O valor não pode ser menor que o débito da inicial **acrescido de 30%**.
- **CLT, art. 899, § 11** (incluído pela Lei 13.467/2017): o depósito recursal pode ser substituído por fiança bancária ou seguro garantia judicial.
- Os tribunais aplicam regras próprias, como o Ato Conjunto TST.CSJT.CGJT 1/2019. Segundo artigos públicos, as apólices são recusadas por falta dos 30% ou por prazo de validade [F3c]. **O agente não diz se o juiz vai aceitar.**

### A5. Transporte de carga: Lei 14.599/2023, Resolução CNSP 472/2024 e ANTT

**Seguros obrigatórios para quem transporta carga de terceiros por frete:**
- **RCTR-C:** acidente com a carga.
- **RC-DC:** desaparecimento da carga.
- **RC-V:** danos a terceiros causados pelo veículo.

Segundo a SUSEP, a lei não criou produto novo: tornou obrigatórios produtos que já existiam [F7].
O RC-V vem da Resolução CNSP 478/2024 [F8].

| Tema | Resolução CNSP 472/2024 [F9] |
|---|---|
| Quem é o segurado | Só o transportador inscrito e ativo no RNTRC da ANTT (arts. 9º e 18). |
| O que o RCTR-C cobre | Colisão, capotagem, abalroamento ou tombamento do veículo; incêndio ou explosão no veículo; incêndio ou explosão em depósito, armazém ou pátio do segurado (art. 10). **Não cobre roubo nem furto.** |
| O que o RC-DC cobre | Desaparecimento total ou parcial da carga por roubo, furto, apropriação indébita, estelionato ou extorsão durante o trânsito. Também cobre em depósito listado na apólice (art. 19). Roubo em depósito é cobertura facultativa (art. 20). |
| Apólice única | Uma apólice vigente de cada tipo, vinculada ao RNTRC (arts. 9º e 18, parágrafo único). Mais de uma faz perder a indenização (art. 38). |
| Averbação | Todo embarque é comunicado antes da saída, com o conhecimento de transporte. O MDF-e vai depois da averbação (art. 40). Sem averbar todos, a seguradora fica isenta (art. 41). |
| PGR | Plano de gerenciamento de risco combinado entre transportador e seguradora (art. 37). |
| Franquia | É proibida no RCTR-C (art. 10, § 2º). No RC-DC é permitida, compatível com o porte do transportador (art. 19, § 5º). |
| Valor | O valor declarado no conhecimento ou documento fiscal (art. 33), até o limite por veículo ou acúmulo (art. 19, §§ 1º e 3º). |
| DDR | A dispensa de direito de regresso no seguro do embarcador **não dispensa** os seguros do transportador (art. 53). Ofício Circular SUSEP 2/2023 [F7]. |
| Pedido do embarcador | Pode exigir cópia da apólice e do PGR na contratação do frete (art. 54). |
| Transição | Os planos antigos, incluindo os de "RCF-DC", tiveram 180 dias para se adaptar (art. 57) [F9, F10]. |

**RCF-DC** era o nome antigo do seguro de desaparecimento de carga. O "F" é de facultativo, porque antes da Lei 14.599 ele não era obrigatório.
Há condições gerais públicas antigas com esse nome [F11]. Hoje a regra fala em RC-DC.
Atenção: o Open Insurance ainda mostra produtos com o nome "RCF-DC" (Sompo e Chubb) [F12]. Por isso o agente reconhece os dois nomes.

**ANTT:**
- Segundo a Revista Apólice, as novas regras valem desde 01/07/2026 [F13]. A ANTT confere eletronicamente as apólices para manter o RNTRC ativo (Resolução ANTT 6.068/2025).
- Ainda segundo a Revista Apólice, MEI e ME que operam como transportadora também precisam dos seguros. O autônomo (TAC) que trabalha só subcontratado fica coberto pela apólice da empresa [F13].
- Segundo a SETCESP, a Deliberação ANTT 293, de 08/10/2026, liga a ANTT à CNseg para validar as apólices. A transportadora autoriza a seguradora a mandar os dados e guarda a capa da apólice para a fiscalização [F14].

**Dono da carga (embarcador):** quem protege a própria carga contrata o seguro de **Transporte Nacional ou Internacional**.
No Open Insurance, a Chubb publica três coberturas [F12]:
- **ampla (A):** quaisquer causas externas, menos as excluídas;
- **restrita (B):** a C mais alagamento, desmoronamento, terremoto etc.;
- **restrita (C):** incêndio, raio, explosão, encalhe etc.

Outros produtos publicados no Open Insurance [F12]:
- transportador aéreo (RCTA-C), aquaviário (RCA-C) e ferroviário (RCTF-C);
- viagem internacional (RCTR-VI-C, "Carta Azul" do Mercosul);
- operador multimodal (RCOTM-C).

### A6. O que as seguradoras e corretoras pedem

**Garantia:**
- O cadastro do tomador passa por análise da seguradora, que dá um limite (capacidade).
- Segundo a página da Tokio Marine (lida pelo resumo da busca, porque a página recusou o acesso direto), os documentos são:
  - fichas cadastrais do tomador e dos acionistas;
  - contrato ou estatuto social;
  - balancete do mês anterior, em certos casos.
- A mesma página diz que a contratação exige corretor nomeado [F15].
- Segundo material da Tokio Marine, a análise usa balanço patrimonial, DRE e questionário de risco [F15b].
- **Não achamos lista oficial única.** A lista de documentos do modelo diz "costuma ser pedido" e "a seguradora confirma".

**Transporte:**
- O questionário do Sincor-SP (QRA Transportadoras) cobre mercadorias, trajetos, frota, embarcadores, gerenciamento de riscos e sinistros [F16].
- O questionário da Tokio Marine pergunta por rastreador e pela empresa de monitoramento [F17].
- Segundo uma plataforma de corretora, há questionários com mais de 50 perguntas [F18].
- **O agente pede só o essencial. O resto fica com o corretor.**


---

## Fontes

| Id | Fonte | URL |
|---|---|---|
| F1 | Circular SUSEP 662/2022, texto integral (cópia pública na UFSJ) | https://ufsj.edu.br/portal2-repositorio/File/proad/circular%20SUSEP%20662-2022.pdf |
| F2 | Lei 14.133/2021 (Planalto) | https://www.planalto.gov.br/ccivil_03/_ato2019-2022/2021/lei/l14133.htm |
| F3a | CPC, Lei 13.105/2015, art. 835 (Planalto) | https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2015/lei/l13105.htm |
| F3b | CLT, art. 899 (Planalto) | https://www.planalto.gov.br/ccivil_03/decreto-lei/del5452.htm |
| F3c | Artigo sobre depósito recursal e os 30% (Legismap) | https://legismap.com.br/conteudos/artigos-e-noticias/o-deposito-recursal-substituido-por-seguro-deve-ter-o-acrescimo-de-30 |
| F4 | MSIG: condições do seguro garantia, setor público, jun/2025 | https://msig.com.br/wp-content/uploads/2025/06/202506_CC_Garantia-Publico.pdf |
| F5 | Zurich: condições do setor público (executante construtor, fornecedor ou prestador) | https://edge.sitecorecloud.io/zurichinsurf8c0-zwpshared-prod-d824/media/project/zurich-headless/brazil/docs/empresariais-garantia/2025/cc-publico-15414639268_2022-65-v202512.pdf |
| F6 | Essor: condições do seguro garantia, setor privado, dez/2023 | https://www.essor.com.br/wp-content/uploads/essor_condicoes_contratuais_seguro_garantia_setor_privado_20dez23.pdf |
| F7 | SUSEP: comunicado de 11/10/2023 (Ofício Circular 2/2023/DIR1) | https://www.gov.br/susep/pt-br/central-de-conteudos/noticias/2023/outubro/susep-emite-comunicado-acerca-de-seguros-de-contratacao-obrigatoria-dos-transportadores-rodoviarios-de-carga |
| F8 | SUSEP: norma do RC-V (Resolução CNSP 478/2024) | https://www.gov.br/susep/pt-br/central-de-conteudos/noticias/2024/dezembro/publicada-norma-sobre-o-seguro-de-responsabilidade-civil-de-veiculo-rc-v-do-transportador-de-cargas |
| F9 | Resolução CNSP 472/2024, texto (Normas Brasil) | https://www.normasbrasil.com.br/norma/resolucao-472-2024_465248.html |
| F10 | Resumo da Resolução 472 (Lefosse) | https://lefosse.com/noticias/susep-publica-resolucao-com-novas-diretrizes-para-o-seguro-de-responsabilidade-civil-dos-transportadores-de-carga |
| F11 | Tokio Marine: condições antigas do RCF-DC | https://www.tokiomarine.com.br/wp-content/uploads/2016/01/201203-RC-do-Transportador-Rodoviário-por-Desaparecimento-de-Carga-RCF-DC.pdf |
| F12 | Open Insurance Brasil: diretório e produtos abertos (fase 1), lidos em 10/11/2026 | https://data.directory.opinbrasil.com.br/participants ; produtos `/open-insurance/products-services/v2/{public-guarantee,transport}` da Chubb (api.chubb.opinb3.com.br), da Mapfre (api-openinsurance.mapfre.com.br) e da Sompo (api.sompo.com.br) |
| F13 | Revista Apólice, 06/07/2026: transporte de cargas já opera sob as novas regras | https://revistaapolice.com.br/2026/07/transporte-de-cargas-ja-opera-sob-novas-regras-do-seguro-obrigatorio/ |
| F14 | SETCESP via CQCS, 20/10/2026: fiscalização dos seguros obrigatórios | https://cqcs.com.br/noticia/fiscalizacao-dos-seguros-obrigatorios-no-trc-o-que-a-transportadora-precisa-fazer/ |
| F15 | Tokio Marine: página do seguro garantia (lida pelo resumo da busca, porque o acesso direto deu 403) | https://tokiomarine.com.br/seguros/seguro-garantia |
| F15b | Tokio Marine: material ao corretor sobre análise de risco | https://marketing.tokiomarine.com.br/Arquivos/e-mails/2019/Corretor/0930_Riscos26/Riscos26.pdf |
| F16 | Revista Apólice, 01/2021: questionário de transporte do Sincor-SP | https://revistaapolice.com.br/2021/01/sincor-sp-disponibiliza-questionario-de-analise-de-seguro-de-transporte |
| F17 | Tokio Marine: questionário de transporte avulso | https://www.tokiomarine.com.br/wp-content/uploads/2016/05/Transporte-Avulsa.doc |
| F18 | Mundo Logística: plataforma que simplifica a contratação | https://mundologistica.com.br/noticias/plataforma-para-simplificar-contratacao-de-seguros-garante-vantagens-ao-transporte-de-cargas |
| F19 | Legismap: seguro de caminhão não protege a carga | https://legismap.com.br/conteudos/artigos-e-noticias/seguro-de-caminhao-garante-a-protecao-da-carga-entenda-as-regras-do-setor |

Ressalvas da pesquisa:
- **F3a e F3b:** o texto dos dois artigos foi conferido pelo resumo da busca e pelo F3c. A página do Planalto não foi lida nesta rodada.
- **F15:** também foi lido pelo resumo da busca, porque a página recusou o acesso direto (403).
- **F9:** o texto vem de um agregador (Normas Brasil). Os artigos citados ainda não foram conferidos no DOU nem na SUSEP: fica para a leitura de quem conhece o ramo.

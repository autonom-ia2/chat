# Modos de falha do Agente de Cotação

As falhas que custaram caro na construção de auto, entre 03/09 e 21/09/2026. **Leia antes de escrever a
primeira linha de um ramo novo.** Cada item traz o que alguém viu, a causa, o que pega a falha antes de
ela chegar ao cliente, se ela vale para outro ramo, a fonte com linha conferida e a origem.

Origem: **produção** (visto em conversa ou cotação real), **teste** (visto em sonda, teste ou revisão),
**memória** (registro do operador, datado; conferir no código antes de confiar).

Quando a fonte não diz o que pega a falha, o item diz isso. Não é esquecimento: é o buraco.

## Fontes

| Sigla | Arquivo |
|---|---|
| E1 … E16, E380 | `docs/audit/2026-09-1x-entrega-<n>-*.md` deste repositório (a entrega no nome) |
| FR | `docs/audit/2026-09-12-frases-do-especialista.md` |
| F1, F2, F3 | `docs/audit/2026-09-13-fatia-1-pdf-rapido.md`, `…-fatia-2-lia-ve-resultados.md`, `2026-09-18-fatia-3-lia-escreve.md` |
| LP | `docs/audit/2026-09-18-lia-promessa-verdadeira.md` |
| E8a | `docs/audit/2026-09-12-entrega-8a-motor-assincrono.md` |
| README, PRD | `docs/insurance/README.md`, `docs/insurance/PRD.md` |
| RNA | `autonomia-adapters: docs/agger/ramos-nao-auto.md` |
| RET | `autonomia-adapters: docs/agger/RETOMADA.md` |
| GAP | `autonomia-adapters: docs/implementation-gap-report.md` |
| MEM | memória do operador, arquivo e data |

---

## A. O que entra no formulário

**A1. Especialista cego para a conversa.** O CPF dito pelo cliente e o PDF da apólice não chegavam: ele
recebia só um bilhete do principal. *Pega:* `specialists/materia_spec.rb`, `answerer_specialist_delegation_spec`.
*Outro ramo:* sim. *Fonte:* E1:8-10, E1:183-195. *Origem:* teste; correção provada em produção.

**A2. Leitura de anexos sem teto de trabalho.** 32 PDFs escaneados davam 32 downloads para devolver zero, e
uma apólice legível ficava de fora. Teto de resultados não é teto de tentativas; identidade do documento era o
nome, não o conteúdo. *Pega:* `Materia::TENTATIVAS`, dedupe por checksum, `materia_spec.rb`. *Outro ramo:* sim
(escritura, laudo). *Fonte:* E1:71-76, E1:108-111. *Origem:* teste.

**A3. Especialista fura o portão de mídia.** Lia PDF com a mídia desligada, porque a regra estava só no caminho
do principal. *Pega:* spec "mídia desligada". *Outro ramo:* sim. *Fonte:* E1:67-70. *Origem:* teste.

**A4. Renovação sem seguradora anterior dá zero preço.** 17 recusas: a ferramenta não tinha onde escrever a
seguradora anterior que o especialista leu no PDF. *Pega:* trava em `condicionais.ts` na conferência gratuita;
leitura de volta. *Outro ramo:* onde houver renovação. *Fonte:* E1:208-219, E2:155-163. *Origem:* produção.

**A5. A mesma seguradora com dois códigos.** HDI é 4 para escolher quem cota e 657 como apólice anterior; sete
cotações pagas recusadas pelo mesmo domínio. *Pega:* domínio publicado no schema e `quote/validate` gratuito
antes do `start`. *Outro ramo:* onde houver referência a outra seguradora. *Fonte:* GAP:147-149, GAP:175-182.
*Origem:* produção.

**A6. Pedido inválido queimando cotação paga.** Não havia conferência gratuita antes da chamada paga. *Pega:*
`quote/validate`, sem rede, antes do `start`. *Outro ramo:* sim. *Fonte:* GAP:145-149. *Origem:* produção.

**A7. Uma ferramenta para vários ramos não diz o que é obrigatório em cada um.** O modelo mandou `cpf: null` e
foi recusado. `strict` não tem obrigatório condicional. *Pega:* precheck síncrono; formulário gerado do schema
(`parametros_spec.rb`, `quote_input_travessia_spec.rb`). *Outro ramo:* **sim, é exatamente o caso.** *Fonte:*
MEM `schema-plano-nao-diz-obrigatorio-por-ramo.md` (08/09), E2:10-15. *Origem:* produção.

**A8. Um campo opcional fora de `required` emudece o turno.** A OpenAI recusa a chamada inteira quando o schema
está malformado; a Lia recebeu três mensagens e respondeu zero, sem nada na tela. *Pega:*
`native/openai_schema_spec.rb`, que percorre o `Registry` inteiro. *Outro ramo:* sim. *Fonte:* MEM
`openai-strict-nao-tem-campo-opcional.md` (08/09). *Origem:* produção.

**A9. Parâmetro nosso com o mesmo nome de uma raiz do adapter.** HTTP 400 e agente mudo. *Pega:* falha dura em
`Native::Base.objeto`. *Outro ramo:* **sim, cada ramo traz raízes próprias.** *Fonte:* FR:80-84. *Origem:* teste.

**A10. Campo de valores fechados publicado sem a lista.** O especialista escalou a moto para humano; o caminhão
mandava "3" em silêncio. *Pega:* guarda no adapter ("todo campo restrito publica valores"). *Outro ramo:* sim.
*Fonte:* E2:165-179. *Origem:* produção.

**A11. O mesmo nome de campo com domínios diferentes.** `periodoUso` muda de domínio entre carro e caminhão.
*Pega:* a fonte não diz; pegou a recusa nomeada do portal. *Outro ramo:* sim. *Fonte:* RNA:175. *Origem:* teste.

**A12. Valor fixo nosso no corpo.** A moto era cotada com o perfil errado, e nada acusava. *Pega:* a fonte não
diz; o estado final é "nenhum parâmetro fixo". *Outro ramo:* sim. *Fonte:* RET:64-66. *Origem:* teste.

**A13. Guarda que cobra, de quem não tem, um dado que a conversa já tem.** Toda cotação de empresa escalou: a
guarda de pessoa jurídica pedia nascimento e sexo do CNPJ, e a cópia do condutor estava atrás de um fornecedor
pago. *Pega:* a fonte não diz; a regra é perguntar de qual pessoa é o dado antes de exigi-lo. *Outro ramo:*
**sim, condomínio e empresarial são pessoa jurídica.** *Fonte:* MEM `guarda-cobrou-campo-de-pessoa-do-cnpj.md`
(20/09). *Origem:* produção.

**A14. Consultar e cotar não cabem no mesmo turno.** A rodada de ferramentas é uma só: quem mandava tudo de uma
vez via a consulta sair e a cotação não. *Pega:* a cotação faz a consulta prévia sozinha. *Outro ramo:* sim, para
qualquer consulta prévia (CEP, imóvel). *Fonte:* E2:123-128, E3:44-49. *Origem:* teste.

**A15. Login de 60 segundos dentro do turno.** *Pega:* sessão viva no turno. *Outro ramo:* sim. *Fonte:*
E2:114-117. *Origem:* teste.

**A16. Indisponibilidade nossa vira pergunta ao cliente.** Sem schema, a ferramenta pedia a placa. *Pega:*
motivo `formulario_indisponivel` antes de qualquer pergunta. *Outro ramo:* sim. *Fonte:* E2:118-122. *Origem:* teste.

**A17. O schema guardado não se renova sozinho.** Foi preciso apagar à mão depois de o adapter mudar; ele só entra
de novo quando a varredura da conexão roda (`connections/sync.rb`, `ScanJob`). *Pega:* nada; issue chat#383. *Outro ramo:* **sim, e piora com dez ramos.** *Fonte:* E2:176-179. *Origem:* produção.

**A18. Padrão omitido cota o caso errado.** `isZeroKm` omitido quer dizer usado. *Pega:* conferência que
pergunta a dúvida. *Outro ramo:* onde um padrão omitido mudar o preço. *Fonte:* E3:27-33. *Origem:* teste.

## B. O portal e o ramo

**B1. Recusa genérica tomada como campo faltando.** Bike e celular ficaram semanas sem cotar: faltava formato,
não campo. *Pega:* capturar a cotação da tela e ler de volta (RNA seção 4). *Outro ramo:* sim. *Fonte:* MEM
`agger-formato-nao-e-campo.md` (07/09). *Origem:* teste.

**B2. Descoberta fora do pacote.** O adapter em produção cotava um ramo com seis já descobertos e pagos:
`scripts/` não entra no build. *Pega:* a fonte não diz teste; conhecimento que o produto usa mora em `src/`.
*Outro ramo:* sim. *Fonte:* RET:42-48, RNA:126-129. *Origem:* produção.

**B3. Capacidade paga sem consumidor.** Recursos prontos no adapter que o chat2you não chamava, relatados como
entrega. *Pega:* a pergunta "quem chama isso?", com exercício ponta a ponta. *Outro ramo:* sim. *Fonte:* MEM
`quatro-capacidades-pagas-sem-consumidor.md` (08-10/09). *Origem:* produção. Conferido em 21/09:
`SEGURADORAS_RENOVACAO` continua sem chamador.

**B4. Coberturas com proporção entre si.** Preencher toda cobertura com o mesmo valor transforma cotação boa em
recusa: danos elétricos até 50% de incêndio; vendaval e impacto de veículos são uma cobertura só. *Pega:* **os
valores padrão** já respeitam a proporção (`ramos/configuracoes.ts`, `valoresDeCobertura`: alagamento fora,
incêndio como base, piso de danos morais; testes em `test/unit/ramos-no-adapter.test.ts`). **O valor informado
pelo cliente não é conferido** (a função não mexe no que já veio preenchido), e a soma de vendaval com impacto só
existe no padrão do condomínio. *Outro ramo:* **é o centro do residencial.** *Fonte:* RNA:45-56, RNA:174.
*Origem:* teste.

**B5. Profissão por seguradora, com códigos diferentes.** A Allianz recusou a cotação inteira porque não tinha
"professor". *Pega:* a fonte não diz teste; o dado vem de `getOptionsBySegFull`. *Outro ramo:* ramos de pessoa e
empresa (atividade); não residencial. *Fonte:* RNA:58-85. *Origem:* teste.

**B6. Correção feita num caminho e esquecida no outro.** O ramo 91 ficou quebrado uma rodada depois de o 81 ser
corrigido. *Pega:* a fonte não diz. *Outro ramo:* sim. *Fonte:* RNA:87-95. *Origem:* teste.

**B7. Campo perdido ao mover o contrato capturado.** Estado civil, renda, `vidas` fora de `configuracoes`.
*Pega:* só a prova contra o portal; nenhum teste unitário pegaria. *Outro ramo:* sim. *Fonte:* RNA:165-181.
*Origem:* teste.

**B8. Escala de valores herdada do ramo vizinho.** O condomínio usava os valores da casa; cada seguradora tem
piso diferente. *Pega:* a fonte não diz. *Outro ramo:* **sim, de residencial para condomínio.** *Fonte:*
RNA:172-173. *Origem:* teste.

**B9. Endereço reduzido ao CEP.** "Logradouro deve ser informado corretamente": `endereco` é texto de exibição,
os campos reais são `imovel*`. *Pega:* a fonte não diz. **Em 21/09 o defeito continua aberto no caminho do
produto:** `schema.ts` marca o endereço do imóvel como `derivado`, mas `enderecoDoImovel` só copia o que recebe,
`quote.ts` diz que ali não há consulta de CEP, e o chat2you manda só CEP e número. A prova de 07/09 não viu porque
injetou o endereço à mão. Pista, não verificada como solução: auto já consulta o CEP no portal (`lookupCep`, em
`src/platforms/agger/http/quote.ts`), e o caminho dos outros ramos (`contratoGenerico`, no mesmo arquivo) não chama. *Outro ramo:* **sim, o imóvel é o bem segurado.**
*Fonte:* RNA:42-43, RNA:177. *Origem:* teste.

**B10. O filtro de seguradoras descarta quem cota.** A Axa deu preço e o filtro a excluía. *Pega:* **no caminho
do produto, nada.** O override `SEGURADORAS_DO_PORTAL` em `ramos/contratos.ts` só é lido pelo script de prova
(`scripts/discovery/provar-ramo-pelo-adapter.ts`); o produto chama `listInsurersForQuote` sem ele. É o modo B3
aplicado a uma correção: existe, e ninguém do produto a chama. *Outro
ramo:* sim. *Fonte:* RNA:184-203. *Origem:* teste.

**B11. Preço tratado como propriedade do ramo.** Preço é da execução; recusa e prazo estourado não são a mesma
coisa. *Pega:* `test/unit/docs-nao-afirmam-preco-orfao.test.ts`, `conhecimento-honesto.test.ts`. *Outro ramo:*
sim. *Fonte:* MEM `agger-preco-e-da-execucao.md` (07/09), RNA:159-161. *Origem:* teste.

**B12. Premissa nunca medida de "uma sessão por login".** Quase se construiu uma fila por corretora; medido, 12
sessões coexistem. *Pega:* `test/contract/agger.sessao-unica.live.test.ts`. *Outro ramo:* sim. *Fonte:* E16:14-26.
*Origem:* teste.

**B13. Alarme falso permanente na tela de Conexões.** O portal manda "conta em uso" em todo login. *Pega:*
`session_spec.rb`, `connection_spec.rb`. *Outro ramo:* sim. *Fonte:* E16:162-171. *Origem:* produção.

**B14. O portal não lista cotações, e timeout depois da criação vira duplicata.** *Pega:* intenção anotada antes
do envio, no máximo uma repetição, marca de envio incerto. *Outro ramo:* sim. *Fonte:* E5:5-12. *Origem:* teste.

**B15. Senha de terceiro em texto claro.** A leitura de volta traz usuário e senha da corretora em cada
seguradora. *Pega:* `stripPortalSecrets`, `CORPO_NUNCA_CAPTURADO`, `destino-seguro.test.ts`. *Outro ramo:*
**sim, capturar contrato de ramo lê esse bloco.** *Fonte:* RNA:205-234. *Origem:* teste.

**B16. Mock escrito na suposição.** Chaves em formato errado e tradução manual incompleta: token virava
`<REDACTED>`, `quoteId` descartado com a consulta paga. *Pega:* conversão mecânica de chaves, contrato real,
teste vivo com portão de ambiente. *Outro ramo:* sim. *Fonte:* GAP:160-163, MEM
`traducao-de-fronteira-nao-e-lista.md` (08/09). *Origem:* produção.

## C. A instrução e o modelo

**C1. Manual gravado no nascimento.** Correções nunca chegavam ao agente 24. *Pega:* o runtime lê o arquivo do
deploy; md5 assinado. *Outro ramo:* sim. *Fonte:* E3:9-15, E380:8-13. *Origem:* produção.

**C2. Coluna com escritores escondidos.** Uma edição era aceita, exibida e ignorada. *Pega:*
`Agent#recusar_se_instrucao_mantida!`. *Outro ramo:* sim. *Fonte:* E380:183-201. *Origem:* teste.

**C3. Escolhas incompletas: turno mudo ou volta calada ao texto velho.** *Pega:*
`responder_escolhas_incompletas_spec.rb`. *Outro ramo:* se o manual do ramo tiver variável da corretora.
*Fonte:* E380:336-344. *Origem:* teste.

**C4. Substituição de variável relê o valor inserido.** "Atende pela corretora $nomeAgente". *Pega:* passada
única, recusa de marcador dentro da escolha. *Outro ramo:* mesmo critério de C3. *Fonte:* E380:552-559. *Origem:* teste.

**C5. Crase no valor do template.** O modelo copia a crase para o WhatsApp. *Pega:* `builder_spec.rb`
("nenhuma variável do arquivo está entre crases") varre todos os manuais em `instrucoes/`, inclusive o de um ramo
novo. Cobre `$variavel` entre crases, não qualquer valor entre crases.
*Outro ramo:* sim. *Fonte:* MEM `instrucao-de-agente-nao-poe-valor-em-crase.md` (08/09). *Origem:* produção.

**C6. Duas regras opostas na mesma instrução.** Vence a mais perto do instante da ação, não a mais nova; a
correção "não repergunte" não funcionou até a outra ser trocada. *Pega:* a fonte não diz teste; pegou a revisão
adversarial. *Outro ramo:* sim. *Fonte:* MEM `instrucao-a-regra-mais-perto-da-acao-vence.md` (21/09). *Origem:* teste.

**C7. Instrução que promete o que o código não tem.** O manual mandava consultar ferramentas inexistentes, e uma
regra invertida passou 35 de 35 exemplos. *Pega:* tabela `PROMESSAS` mais md5 do texto
(`builder_instrucao_do_*_spec.rb`). *Outro ramo:* sim. *Fonte:* E9:243, E3:67. *Origem:* produção e teste.

**C8. Fonte concorrente para dúvida de cobertura.** A busca na web podia responder sem cláusula. *Pega:*
`answerer_duvida_durante_cotacao_spec.rb`. *Outro ramo:* sim. *Fonte:* E9:62-69. *Origem:* teste.

**C9. Ferramenta ligada no código e ausente no agente que já existe.** Os slugs são gravados só na criação.
*Pega:* lista mantida do deploy. *Outro ramo:* **sim, e é o mesmo buraco do especialista novo (receita, fase 5).**
*Fonte:* E2:99-104, F2:234-241. *Origem:* teste.

**C10. Turno morre em silêncio com 503 da OpenAI.** *Pega:* nada; issue chat#384. *Outro ramo:* sim. *Fonte:*
E2:181-184. *Origem:* produção.

**C11. As nossas palavras viram a voz do modelo.** "Frase que encerra a busca" virou "A busca foi concluída"; "o
comparativo chega aqui" virou a fala da Lia; "parafraseie" fez a Lia herdar a voz do especialista. *Pega:* não há
teste de voz; direção sem frase de exemplo, e leitura da conversa por gente. *Outro ramo:* sim. *Fonte:* conversa
6984, execução 49, e PR #575 (21/09). *Origem:* produção.

## D. O que chega ao cliente

**D1. O canal de entrega usado para falar com o modelo.** O cliente leu "faltam estes dados: insured.document.
Pergunte ao cliente…". *Pega:* `Progress#sanitize`, `TextoAoCliente`. *Outro ramo:* sim. *Fonte:* MEM
`canal-de-entrega-nao-e-canal-do-modelo.md` (08/09). *Origem:* produção.

**D2. Aceite que afirma sucesso antes de qualquer envio.** "Cotação enviada" e a falha cinco segundos depois.
*Pega:* a fonte não diz teste; a descrição do papel foi corrigida. *Outro ramo:* sim. *Fonte:* FR:132-134. *Origem:* produção.

**D3. A peneira de saída descarta a entrega ou mutila o link.** Um nome de grupo do formulário casava com a URL
do PDF. *Pega:* `texto_ao_cliente_spec.rb`. *Outro ramo:* **sim, os grupos mudam por ramo.** *Fonte:* FR:234-245.
*Origem:* teste.

**D4. O que a peneira não enxerga.** "Chegaram três opções", "volto em cinco minutos", "a Porto respondeu"
passam inteiros. *Pega:* nada, por decisão: a fronteira está no manual. *Outro ramo:* sim. *Fonte:* FR:164-171.
*Origem:* teste.

**D5. Truncamento silencioso.** Ofertas cortadas marcadas como entregues. *Pega:* a fonte não diz. *Outro ramo:*
depende de quantas seguradoras. *Fonte:* FR:58-72. *Origem:* teste.

**D6. Frase fixa que mente.** "Os preços acima são os que chegaram", sem preço acima. *Pega:*
`encerramento_spec`, `async_run_job_encerramento_parcial_spec.rb`. *Outro ramo:* sim. *Fonte:* E8a:598-604.
*Origem:* teste.

**D7. Frase de classe definida na instância.** A frase de seguros nunca saiu. *Pega:*
`base_contrato_de_nivel_spec.rb`, que varre o `Registry`. *Outro ramo:* sim. *Fonte:* E4:7-12. *Origem:* teste.

**D8. Promessa falsa e voz de processo interno.** "As três mais baratas" com onze no anexo; "novas tentativas
podem gerar custo"; "um atendente vai retomar" sem ninguém acionado. *Pega:*
`builder_voz_sem_processo_interno_spec.rb`, `insurance_quote_result_spec.rb`. *Outro ramo:* sim. *Fonte:*
LP:9-12. *Origem:* produção.

**D9. Conferência de preço aceita valor trocado.** Valores de duas seguradoras invertidos, mensal chamado de
total. *Pega:* `conferencia_de_precos_spec.rb`; lacunas abertas em #455. *Outro ramo:* sim. *Fonte:* F3:77-89.
*Origem:* teste.

**D10. Período do preço errado.** Mensal e anual ordenados pelo número cru. *Pega:* `premium_text_spec.rb`,
`quote_offers_spec.rb`. *Outro ramo:* se o ramo tiver assinatura mensal. *Fonte:* E13:5-7, E13:306-312. *Origem:* produção.

**D11. Forma do dado colapsada.** Um `null` de seguradora recusada derrubava o resultado inteiro. *Pega:* fixture
no formato bruto. *Outro ramo:* sim. *Fonte:* E13:132, E13:223. *Origem:* teste.

**D12. Motivo de recusa filtrado por lista de palavras.** Texto de conta e de pessoa liberado ao modelo, cinco
rodadas furadas. *Pega:* molde fechado com duas categorias; na dúvida, genérico (`motivo_da_recusa_spec.rb`).
*Outro ramo:* **sim; as categorias hoje são só de veículo e região.** *Fonte:* F2:258-277. *Origem:* teste.

## E. O motor assíncrono e a entrega

**E1. Escrita do estado copiada da memória apaga a de outro processo.** *Pega:* `merge_handle!` no banco; #418
aberto. *Outro ramo:* sim. *Fonte:* E5:28-32, E8a:742-760. *Origem:* teste.

**E2. Pedido repetido abre cotação nova, e prova repetida não mede nada.** A guarda vale 24 horas. *Pega:*
`bound_pedido_repetido_spec.rb`; prova sempre com dado novo. *Outro ramo:* sim. *Fonte:* E10:8-11, MEM
`prova-real-precisa-de-dado-novo.md` (12/09). *Origem:* teste. O método citado nas fontes, `pedido_ainda_vale?`,
hoje é `ToolRun#conta_como_pedido?`.

**E3. Recusa sem registro.** Ramo desconhecido tentava 60 vezes em 7 minutos sem uma linha de log. *Pega:*
produtor único `Tools::Recusa`, `spec/support/varredura_de_recusas.rb`. *Outro ramo:* sim. *Fonte:* E6:7-10.
*Origem:* teste.

**E4. Conexão presa em `auth_required`.** A Lia parou de cotar em silêncio. *Pega:* a fonte não diz teste;
corrigido no adapter #48. *Outro ramo:* sim. *Fonte:* E6:74-77. *Origem:* produção.

**E5. Emissão contada como entrega.** *Pega:* `Tools::EntregaAceita`. *Outro ramo:* sim. *Fonte:* E8a:164-168.
*Origem:* teste.

**E6. Estado mudo e fecho que contradiz.** Cliente sem resultado e sem desfecho, ou o fecho saindo antes dos
preços adiados. *Pega:* `insurance_quote_nenhum_estado_mudo_spec.rb`, `encerramento_spec`,
`async_run_job_pdf_antes_do_adiamento_spec.rb`. *Outro ramo:* sim. *Fonte:* E8a:203-209, F1:555-562. *Origem:* teste.

**E7. Cotação que só encerra com `completed`.** O portal não declara `completed` quando há recusa: toda cotação
rodava sete minutos. *Pega:* `todas_com_desfecho?` com duas leituras iguais. **Medido só em auto.** *Outro ramo:*
sim. *Fonte:* F1:19-28. *Origem:* produção.

**E8. O PDF.** Uma em cinco gerações falha, cada pedido devolve outra URL, e a URL carrega dado pessoal. *Pega:*
teto de três tentativas, procura da mensagem pelo token, reserva sem link. *Outro ramo:* sim. *Fonte:* F1:26-35,
E11:152-158. *Origem:* produção.

**E9. Download do portal sem guarda de rede.** *Pega:* `SafeFetch`, `entrega_de_arquivo_spec.rb`. *Outro ramo:*
motor comum. *Fonte:* E11:268-305. *Origem:* teste.

**E10. Mensagem no banco contada como entregue.** *Pega:* `VigiaDeEnvio`, `PendenciaDeEnvio`. *Outro ramo:*
motor comum. *Fonte:* E11:417-425. *Origem:* teste.

**E11. Publicação adiada que falha uma vez não tenta de novo.** *Pega:* nada; #425 aberta. *Outro ramo:* sim.
*Fonte:* F2:889-896. *Origem:* teste.

**E12. Ferramenta derivada de outra execução.** A ferramenta recebe o `ToolRun` inteiro e pode forjar aceite
(#419). *Outro ramo:* sim. *Fonte:* MEM `ferramenta-assincrona-com-origem.md` (12/09), E8a:913-930. *Origem:* teste.

**E13. Desenho assíncrono para o que é só exibição.** Sete rodadas, cada uma com uma corrida nova. *Pega:* trocar
o desenho por ferramenta síncrona. *Outro ramo:* sim. *Fonte:* F2:1004-1008. *Origem:* teste.

**E14. Rollback e deploy com trabalho em andamento.** O deploy mata o processo em 10 segundos, não em 25. *Pega:*
script do passo 1 do rollback; nenhum teste para a morte do processo. *Outro ramo:* sim. *Fonte:* F1:597-624,
F1:731-738. *Origem:* teste.

**E15. O fecho que repete a legenda.** Duas mensagens com um segundo de diferença dizendo a mesma coisa; e o
varredor, depois de um deploy, publicando o mesmo fecho minutos mais tarde. *Pega:* `encerramento_spec` (24
testes reprovam quando o fecho volta). *Outro ramo:* sim. *Fonte:* PR #575 (21/09). *Origem:* produção.

## F. Medição, prova e guardas

**F1. Regra escrita só em comentário.** A janela da medida sem a borda de cima punha a cotação de 01/10 na fatura
de setembro. *Pega:* `medida_spec`. *Outro ramo:* sim. *Fonte:* E7:105-126. *Origem:* teste.

**F2. Contar a unidade errada.** A corretora paga por seguradora acionada, não por execução. *Pega:*
`QuoteOffers#acionadas`. *Outro ramo:* sim. *Fonte:* E7:23-26. *Origem:* produção.

**F3. Teste que passa sem exercitar.** "CI verde" sem rspec; exemplo que nunca disparava a regra; tradução
comparada com ela mesma. *Pega:* mutação obrigatória e leitura do resultado em JSON. *Outro ramo:* sim. *Fonte:*
MEM `testar-direito-ci-desligado.md` (21/09), FR:242-245. *Origem:* teste.

**F4. Guarda de prosa por palavra.** Acusava a verdade medida e aprovava a premissa falsa. *Pega:* não usar: fato
por canário, prosa por leitura ou assinatura. *Outro ramo:* sim. *Fonte:* E16:60-66, E16:129-145. *Origem:* teste.

**F5. "Zero regex" sem guarda.** Uma regex passou por autor, revisão e CI. *Pega:*
`test/unit/sem-regex-no-codigo.test.ts` (adapter). *Outro ramo:* sim. *Fonte:* RET:20-23, MEM
`regra-so-vale-com-guarda.md` (07/09). *Origem:* teste.

**F6. A conversa de teste com um humano como responsável.** A Lia não responde por desenho, e a suíte esperou 180
segundos por uma cotação que nunca viria. *Pega:* conferir o responsável antes de rodar; #573. *Outro ramo:* sim.
*Fonte:* 21/09, conversa 6984. *Origem:* produção.

**F7. Instrução maior que o histórico aceita.** A instrução da Lia passou de 20.000 caracteres e o histórico de
versões tem esse teto, menor que o do agente. Ficou vermelho na `main` sem ninguém ver. *Pega:*
`instruction_version_spec.rb`, **na #578, aberta em 21/09**; na `main` ainda não há guarda. *Outro ramo:* **sim, cada manual de ramo aumenta a instrução.** *Fonte:*
21/09. *Origem:* teste.

---

## O que as fontes não cobrem fora de auto

É a lista do que o piloto de residencial vai ter de descobrir, e não pode supor.

- **Motivo de recusa de imóvel.** As categorias hoje são só veículo e região; recusas de residencial e condomínio
  já registradas saem genéricas (F2:71-79, F2:1141-1148).
- **O formulário do especialista, as travas, as descrições e os sinônimos existem só para auto.** O chat2you busca
  o schema com a constante de auto (`declaracao.rb`).
- **Nenhuma prova pelo chat2you fora de auto.** O que existe é o adapter contra o portal, com dado fictício.
- **Nada equivale à consulta de placa** para o imóvel, e não há regra de "sem X não cota" para ele.
- **A proporção entre coberturas só é garantida nos valores padrão.** O valor que o cliente informa não é
  conferido, e não há regra de como explicar a proporção ao cliente.
- **O endereço do imóvel não é derivado do CEP** no caminho do produto, embora o schema diga que é.
- **A correção do filtro de seguradoras não chega ao produto.**
- **Os campos fora de auto não têm descrição nem valores** no schema do adapter.
- **Profissão e atividade:** a fonte diz onde buscar, não como perguntar, casar o nome dito com a lista de cada
  seguradora, nem o que fazer quando uma não tem a profissão.
- **O fechamento pelas duas leituras iguais** foi medido só em auto.
- **Período do preço, bônus e seguradora anterior** foram medidos só em auto.
- **Pisos por seguradora** estão descritos sem mecanismo de escolha.
- **O valor padrão fora de auto cota sobre dado falso** quando o campo é do cliente (o aluguel de 2000 no ramo 46,
  `schema.ts`). Nenhuma auditoria trata disso.
- **Pessoa jurídica fora de auto** nunca foi discutida, embora condomínio e empresarial sejam PJ.

## Contradições entre as fontes

Quem ler as fontes originais vai encontrar estas. A primeira linha de cada uma é a que vale hoje.

- **Sessão única do portal.** Vale E16:14-26 (medido: logins coexistem). PRD:112-124 e README:18 dizem o contrário.
- **Quantos endereços devolvem senha.** RET:156-157 diz quatro, incluindo `quoteCalculations`; RNA:207 diz três.
  Trate os quatro como sensíveis.
- **Quantos ramos cotam.** Vale RNA:140: o ramo 93 não devolve preço. RET:18 diz "onze, todos provados".
- **`packageType`.** Vale E13:309-312: é a marca de assinatura mensal. E13:33-35 diz o contrário e foi corrigido
  no mesmo documento.
- **Quem escreve preço e nome de seguradora.** Vale F3:5-7: a Lia escreve, o código confere. FR:19-20 foi revogado.
- **Travessão no separador do item e do nome do arquivo.** Vale FR:21-23 (trocados por dois pontos e vírgula),
  conferido no código em 21/09. A memória que diz o contrário está desatualizada.
- **Handoff.** LP:9 diz que a integração do handoff com a Lia não existe, e a #449 continua aberta. README:15 diz
  "pelo `handoff_rule` existente". Em 21/09 a escalada pelo funil do CRM atribuiu o humano na conversa certa (prova
  das 09:25). **Se isso fecha a #449 não foi conferido**: confira antes de prometer atendente num ramo novo.
- **Renovação.** PRD:2124 a põe fora do MVP; as entregas 1, 2 e 13 a tratam como central e entregue. Decisão que
  mudou no caminho, sem registro de quando.

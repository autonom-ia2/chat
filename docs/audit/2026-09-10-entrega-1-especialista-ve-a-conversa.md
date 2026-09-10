# 2026-09-10 · Entrega 1 · O especialista passa a enxergar a conversa

Plano do Agente de Cotação (épico #291), 5ª da ordem. Issue #374. Branch
`feat/entrega-1-especialista-ve-a-conversa`.

## O problema

O especialista de carro não via a conversa: recebia um bilhete escrito pelo principal. Se o cliente
informou o CPF e o principal não o copiou, o CPF não existia para ele; se o cliente mandou o PDF da
apólice, o especialista nem sabia que havia um documento. Primeira das duas paredes entre a palavra
do cliente e a seguradora — e o que faz a renovação funcionar: a apólice chega nele, e dela sai o
bônus.

## Decisões

- **Uma regra só para os dois agentes.** O histórico capado (últimos 16 pares; 4 mil chars por
  item; 40 mil no total, cortando do mais antigo) e a cerca de documentos (moldura de dado
  não-confiável, nome sanitizado) saíram do `PromptBuilder` para `PromptParts` — principal e
  especialista sob o MESMO teto e a MESMA moldura. Copiar seria valor em dois lugares.
- **O que o especialista lê** (`Specialists::Materia`), nesta ordem: aviso "CONVERSA ATÉ AQUI"; a
  conversa pública (`messages.chat`: nunca nota privada nem atividade — as duas vozes, porque sem a
  pergunta do atendente "04297912678" é só um número de 11 dígitos); os PDFs (deste turno, já
  extraídos pelo principal; e das mensagens anteriores DO CLIENTE, `incoming`, anteriores à que
  abriu o turno, por `MessageMedia#documents` — sem transcrever áudio nem baixar imagem), sem
  repetir arquivo, teto de 3; e por último o bilhete ("PEDIDO DO ATENDENTE"), que continua sendo a
  última palavra.
- **Termo 6 ("nada que o cliente não tenha escrito ou anexado")** lido como: nada de fora da
  conversa pública deste cliente. As respostas do atendente ao cliente ENTRAM (fazem parte da
  conversa e dão o rótulo aos dados); nota privada, atividade, instrução, outra conversa, base de
  conhecimento: nunca. Se o Rodrigo quiser só a voz do cliente, é um filtro de papel em `Materia`.
- **Sem mudança na instrução do especialista** — isso é a entrega 3. O aviso de "dado para leitura"
  vai no próprio input, como a cerca dos documentos.
- Falha na extração dos anexos anteriores não derruba o especialista (segue com o que tem); a
  primeira versão da consulta levantava `StatementInvalid` escondida pelo `rescue` — a spec que
  exige `MessageMedia.new` ser chamado é o que pegou.

## Termos

1. Recebe histórico + documentos + pedido — `runner_spec` "a conversa vem antes do bilhete",
   "os documentos deste turno chegam cercados".
2. CPF escrito pelo cliente, não repetido no pedido, chega — `answerer_specialist_delegation_spec`
   "passes the conversation to the specialist…" (o principal repassa a MESMA conversa e os MESMOS
   documentos que recebeu). Em produção: só prova real (a Lia decide o bilhete).
3. PDF de apólice alimenta ≥ 4 campos — o texto do PDF chega cercado (`materia_spec`); o
   preenchimento é do modelo (instrução v6, entrega 3). Prova real pendente (rodada de renovação).
4. Cortando a passagem, some — mutação M1 (runner só com o bilhete) e M6 (principal não repassa).
5. Teto; o mais antigo sai — `materia_spec` "o historico tem teto"; mutação M3.
6. Nada além do que o cliente escreveu/anexou — `materia_spec` "so mensagens publicas do cliente";
   mutações M4 e M8.

## Validação (antes do Codex)

- Arquivos tocados (8 specs): 84 exemplos, 0 falhas, 0 erros de carga. Suíte ampla (`agents`,
  `jobs/agents`, `models/agents`, `insurance`): 728 exemplos, 0 falhas. Rubocop: 0 ofensas em 10 arquivos.
- Mutações (8, restauração em memória com `assert`; cada uma reprova o exemplo que a nomeia): runner só
  com o bilhete; matéria sem documentos; teto cortando o mais recente; anexos anteriores incluindo nota
  privada e atendente; sem dedupe de arquivo; principal não repassa histórico/documentos; `documents`
  transcrevendo áudio; anexos anteriores sem respeitar a origem do turno.
- Não feito: conversa real (termo 2 depende de o principal omitir o CPF no bilhete — não controlável;
  termo 3 exige apólice em PDF numa renovação real — rodada paga). Ambos ficam para prova ao vivo com
  autorização.

## Codex — rodada 1 (REPROVADO) e o que mudou

Achados de código, todos corrigidos no mesmo commit:

- **P2 · portão de mídia ignorado.** `Materia#anteriores` extraía PDF com `operate_media` desligado
  (ENV `AI_AGENT_MEDIA` ou `config['operate_media']`), enquanto o principal entregava documentos
  vazios. Agora o especialista passa pelo MESMO `Config.operate_media_enabled?(agent)`; desligado, não
  lê anexo anterior nenhum. Spec "mídia desligada"; mutação M12.
- **P2 · identidade por nome de arquivo.** Dois `documento.pdf` diferentes viravam um; a mesma
  apólice mandada duas vezes com nomes diferentes entrava duas. A identidade passou a ser o
  CONTEÚDO: o `checksum` que o ActiveStorage calcula no upload, que agora viaja no documento
  extraído (`{name:, text:, checksum:}`). O que o principal já extraiu neste turno (mesmo checksum)
  não é lido de novo; entre os candidatos, o mesmo conteúdo entra uma vez. Spec "não lê de novo";
  mutações M5, M9, M13.
- **P2 · teto do extrator antes do dedupe.** `MessageMedia#documents` cortava nos 2 primeiros PDFs
  antes de extrair e antes do `uniq`: dois PDFs do debounce (já lidos pelo principal) eram lidos de
  novo e descartados, e uma apólice mais antiga não entrava embora sobrasse vaga; dois escaneados sem
  texto bloqueavam uma legível. Agora `Materia#documentos` calcula as VAGAS que sobram dos deste
  turno, exclui do candidatos o que já entrou, e `documents(limit:)` extrai preguiçosamente até
  preencher as vagas com PDFs LEGÍVEIS (um sem camada de texto não ocupa vaga). O caminho do
  principal (`extract`) não mudou. Specs "preenchem só as vagas", "não ocupa vaga"; mutações M10, M11.
- **P3 · comentários prometendo mais que o código.** "Mesma janela do histórico" virou "mesmo número,
  mas contado em anexos — um PDF pode ser mais antigo que a conversa que o especialista vê"; "o
  bilhete é a última palavra" virou "é a posição no prompt, não autorização: o catálogo do
  especialista decide o que ele pode fazer, e o modelo se faz".
- **Principal idêntico.** `Historico.normalizar` aceitava chave string além de símbolo; o
  `PromptBuilder` antigo só aceitava símbolo. Voltou a só símbolo — nenhum chamador de produção
  passa string (`Responder#history`, `history_param` dos controllers, `sanitize_history`,
  `sanitized_history` constroem símbolos), mas "idêntico" tem de ser literal.

O que o Codex confirmou e fica registrado:

- A mensagem que abriu o turno ESTÁ no histórico (`Responder#history` mapeia todos os
  `recent_messages`, sem excluir a última incoming): um CPF escrito neste turno chega ao
  especialista pela conversa, não só pelo bilhete. Ressalva: o corte por item é 4 mil caracteres; o
  que vier depois disso numa mensagem gigante chega ao principal pela `query` mas não ao
  especialista.
- Termo 6, leitura registrada: entra o que o cliente VIU — as mensagens públicas da conversa,
  inclusive as de um atendente humano, de outro agente ou um template público (`Message.chat` exclui
  só privadas e atividades). O termo literal ("nada que o cliente não tenha escrito ou anexado")
  seria falso sem a resposta do atendente: sem a pergunta, "04297912678" é só um número.
- `origin_message_id` é o gatilho vencedor do debounce (normalmente a ÚLTIMA mensagem do turno); o
  PDF mandado antes do texto no mesmo turno vem por `@documents` do principal e é excluído dos
  anteriores pelo checksum.
- Testar e Copiloto passam `delivery: nil`: não consultam anexos anteriores.
- Custo: não há cache de extração; cada chamada do especialista relê os anexos anteriores que
  faltam. O teto de RESULTADOS (3) não limitava o trabalho: o Codex (rodada 2) mostrou 32 candidatos
  escaneados sem texto = 32 downloads e 32 extrações para devolver zero. Por isso existe
  `TENTATIVAS` (6 extrações por chamada, ver abaixo). Não medido em apólice real nesta entrega; o
  turno é limitado pelo timeout HTTP por requisição (120 s), não por um prazo total.
- Injeção: o aviso e o bilhete são mensagens `user`; a posição não dá autoridade. O que o
  especialista PODE fazer é o catálogo dele (`specialist_tools`); o histórico e os PDFs entram como
  dado, cercados — igual ao principal. Não há verificação de correspondência entre o pedido do
  principal e a ferramenta chamada; isso é anterior a esta entrega.

Validação da rodada 2: specs tocadas 87 exemplos, 0 falhas; mutações 13/13 reprovam o exemplo
que as nomeia; suíte ampla 731 exemplos, 0 falhas; rubocop 0 ofensas.

CI da PR em dc290b2a8f: 11/12 verdes; `RSpec (3/8)` falhou em `spec/models/conversation_spec.rb:1182`
("expected 3602.0 to be within 1 of 1 hour") — spec do core do Chatwoot sobre tempo de resposta, fora
deste diff; relógio do runner. Reavaliado no SHA seguinte.

## Codex — rodada 2 (REPROVADO) e o que mudou

- **P2 · duplicata deste turno ocupa vaga.** O principal (`extract`) não deduplica: a mesma apólice
  mandada duas vezes no debounce chegava em dobro e o especialista contava duas vagas — com CRLV e
  CNH anteriores, um ficava de fora. `Materia#documentos` passa os deste turno por `distintos`
  (checksum; sem checksum é sempre distinto) ANTES de calcular as vagas. Spec "conta uma vaga";
  mutação M14.
- **P2 · o teto de resultados não limitava a extração.** A cadeia preguiçosa seguia até achar
  `limit` legíveis: 32 candidatos escaneados = 32 downloads (~160 MB) e 32 extrações síncronas para
  devolver zero, por chamada. `MessageMedia#documents(limit:, attempts:)` separa RESULTADOS de
  TENTATIVAS: elege até `attempts` PDFs e só então extrai até `limit` legíveis; `Materia::TENTATIVAS
  = 6` (três legíveis mesmo com três escaneados no caminho). `attempts` igual a `limit` é o
  comportamento do principal, que continua em `collect_documents`. Spec "tem teto"; mutação M15.
- **P3 · helper da spec fora do caminho real.** `lidos_pelo_principal` chamava `documents`; o
  Responder chama `extract`. Agora `extract.documents` — o que o principal produz de verdade,
  inclusive a duplicata.
- Ressalva do Codex, não corrigida (não há produtor conhecido do estado): o `uniq` por checksum em
  `ineditos` vem antes da elegibilidade; dois anexos com o mesmo blob e metadados divergentes (um
  `file_type` que o extrator recusa) poderiam esconder o elegível.

Validação da rodada 3: specs tocadas 89 exemplos, 0 falhas; mutações 15/15 reprovam o exemplo
que as nomeia; suíte ampla 733 exemplos, 0 falhas; rubocop 0 ofensas.

## Codex — rodada 3: APROVADO (código) em `0ff75a221f`

Sem P1/P2 novos, sem regressão no principal. Confirmado pelo revisor: a dedupe deste turno vem
antes das vagas; o teto de tentativas materializa até 6 elegíveis e só então extrai até as vagas;
a seleção não baixa arquivo (tipo, blob, MIME e tamanho vêm do preload); o principal segue em
`extract` → `collect_documents`. Ressalvas registradas: checksum do ActiveStorage é MD5 (identidade
prática, não prova criptográfica); o teto limita TRABALHO, não duração — até 6 PDFs de 5 MB por
chamada, sem cache, latência real por medir.

**O que esta aprovação NÃO é:** prova dos termos 2 e 3. CPF chegando ao formulário sem estar no
bilhete e PDF de apólice preenchendo ≥4 campos da renovação exigem uma rodada real (paga), com
autorização do Rodrigo, depois do deploy.

## Prova real em produção — 10/09/2026, 21:49Z–22:05Z (VERDE; uma cotação paga, autorizada)

Merge da PR #375 → main `c677e68326` (21:14Z); deploy Hub2You concluído 21:48Z (instância
`i-06e3f3481f6cb8818` na imagem `c677e68326`). Conversa 5045 da conta 16 (Lia, agente 24), pelo
WhatsApp do Rodrigo. Apólice real de teste (HDI, 4 páginas, texto extraível), com autorização.

| Hora (Z) | Mensagem (id) | O que aconteceu |
|---|---|---|
| 21:49:56 | cliente, 298367: "Quero renovar o seguro do meu carro. Meu CPF é 04297912678." | Lia pede só o CEP (298368) — a placa QNX9533 estava na conversa de mais cedo |
| 22:02:33 | cliente, 298395: PDF da apólice (anexo 3, `application/pdf`, 17 270 bytes) + "o endereço está nela" | Lia lê o PDF e pergunta (298396): "A apólice anexada está em outro CPF e identifica o veículo de placa HIK9383. A renovação é desse veículo?" — sem cotar, custo zero |
| 22:04:31 | cliente, 298405: "Sim, é esse veículo mesmo. O seguro fica no meu CPF. Pode cotar a renovação." | **Execução 7 aberta às 22:04:52** (`running`, `origin_message_id` 298405); Lia (298411): "Vou seguir com a renovação do veículo de placa HIK9383, usando o endereço de pernoite da apólice atual." |

`arguments` da execução 7 (lido por psql via SSM, read-only):

```
{"cep": "31110290", "cpf": "04297912678", "nome": null, "bonus": 9, "dados": "{}", "placa": "HIK9383",
 "numero": null, "produto": "auto", "renovacao": true, "sinistros": 1}
```

Conferido contra o PDF (`pdftotext`): CEP Pernoite 31110-290; Placa/UF HIK9383; Qtde Sinistros 1;
Classe de Bônus 09. Tudo bate.

**Termo 2 (CPF que o cliente escreveu chega ao formulário):** o CPF foi dito UMA vez, duas mensagens
antes do turno que abriu a cotação, e não aparece nem no texto desse turno nem no PDF (que está em
outro CPF). Chegou em `arguments.cpf`. O que continua não observável é o bilhete do principal (não é
persistido); a travessia pela conversa está provada por mutação (M1/M6) e aqui pelo dado.

**Termo 3 (PDF alimenta ≥4 campos da renovação):** cinco campos vieram do PDF — `placa`, `cep`,
`renovacao`, `bonus`, `sinistros` — com a ferramenta de 10 parâmetros de hoje (a de ~90 é a entrega 2).

**A prova mais forte é a do caminho novo:** no turno que abriu a cotação (298405) o principal NÃO
tinha o PDF — o anexo estava na mensagem anterior (298395), fora de `current_turn_incoming`, e o
texto do PDF não vive no histórico. Bônus 9, sinistros 1 e CEP 31110290 só podiam chegar ao
formulário pelo especialista lendo o anexo anterior do cliente (`Materia#anteriores`), que é
exatamente o que esta entrega construiu. Antes dela, o especialista teria só o bilhete.

Custo da rodada: uma cotação (execução 7). Latência do turno com leitura do PDF anterior: mensagem
22:04:31 → execução 22:04:52 → resposta 22:05:07 (~36 s, dentro do normal dos turnos com cotação).

### Desfecho da execução 7: zero preço — causa-raiz (não é desta entrega)

Às 22:09:03Z a execução 7 encerrou `done` com `entregues: []` e a Lia disse "Não consegui concluir a
cotação agora. Um atendente vai retomar daqui." Lido no portal (poll read-only pelo adapter, conta de
teste = mesma corretora): cotação `e39fb2c9…:1` com status `failed`, **17 seguradoras, todas
`declined`**. Nenhuma linha de erro no worker (as de domínio não saem em produção) nem no Lambda (só
START/END/REPORT; o `quote/start` levou 25,6 s, normal).

**Causa:** o formulário foi com `renovacao: true` + `bonus: 9` + `sinistros: 1` e **sem a apólice
anterior**. O adapter documenta e mediu isso em 05/09 (`quote-input.ts:299`, `field-contracts.json`
`seguradoraAnteriorId` obrigatório quando `isRenewal`): a mesma pessoa e o mesmo veículo, cotação nova
= 12 preços; marcada como renovação sem `previousInsurerCode`/`previousPolicyNumber`/
`previousPolicyEndDate` = 17 `declined`. O chat2you nunca envia esses três: `AutoRenewal#to_input` só
manda `isRenewal`, `bonusClass`, `previousClaimsCount`, e a ferramenta de hoje (10 parâmetros) não
tem campo para a seguradora anterior — a apólice dizia "HDI", o especialista leu, e não tinha onde
escrever.

**Consequência, pré-existente a esta entrega:** hoje TODA renovação pela Lia (`renovacao: true`)
termina em zero preço. A entrega 2 (ferramenta com os ~90 parâmetros, inclusive os 34 códigos de
seguradora anterior já aprovados em 10/09) é o que resolve. Registrado em issue própria.

**O que a entrega 1 provou mesmo assim:** o dado atravessou — CPF da conversa e cinco campos do PDF
anterior chegaram ao formulário. O portal recusou por um campo que a ferramenta ainda não tem.

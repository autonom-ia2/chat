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

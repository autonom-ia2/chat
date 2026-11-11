# Base de clientes para seguros — desenho da carteira

Épico autonom-ia2/chat#1240. Escrito em 11/11/2026, a partir da conversa com o Rodrigo na sessão "Base de Clientes".
Substitui, para contas do segmento Seguros, o recorte do `PRD-F1.md` (que tratava a base de clientes de qualquer
negócio). O que o PRD-F1 decidiu sobre leitura da planilha, consentimento e desfazer continua valendo.

## 1. Intenção

Toda corretora que entra no chat2you tem uma carteira: as apólices que ela já vendeu. Hoje essa carteira mora em
outro lugar (sistema de gestão, portal da seguradora, planilha, pasta de PDFs) e o chat2you não sabe dela. Por isso
não consegue fazer o que mais dá dinheiro recorrente à corretora: **renovar o seguro antes de vencer**.

O objetivo é a corretora trazer a carteira uma vez, ver os seguros de cada pessoa na ficha, e o chat2you puxar cada
renovação para o funil na hora certa, já com a cotação pronta quando possível, até o card fechar em "Renovou".

**Por que agora.** O segmento Seguros já tem vocabulário, funis prontos (Renovação, Sinistro, Endosso) e a Lia cota
renovação pelo Agger. Falta a peça do meio: a apólice.

**Concorrência (pesquisa de 11/11).** Os sistemas de gestão (Segfy, Quiver/Agger ONE) giram em torno da apólice, mas
não têm IA no WhatsApp. A Segura (segura.ai) tem IA no WhatsApp e funil de renovação, mas só lê o próprio sistema.
Nenhum mostra importar carteira de qualquer origem e trabalhar a renovação no WhatsApp oficial. Esse é o espaço.

## 2. Metas, fora e anti-metas

**Metas**
- Trazer a carteira por três caminhos: conexão Agger, PDFs de apólice e planilha.
- Guardar cada apólice com o PDF, ligada ao contato (e à empresa quando o segurado é CNPJ).
- Mostrar os seguros na ficha do contato e filtrar Relacionamentos por ramo, seguradora e vencimento.
- Criar o card de renovação N dias antes do fim da vigência, no funil e etapa que a corretora escolheu.
- Cotar a renovação sozinho quando houver Agger com cotação liberada, e entregar a proposta pela campanha ou pela
  pessoa.

**Primeiro o perfil Corretora.** Saúde e benefícios vem depois, reaproveitando tabelas, importação e telas; soma só o
que é dele (empresa contratante com vidas, aniversário do contrato no lugar do vencimento).

**Fora (agora)**
- Comissão, extrato, sinistro e endosso como dados. O Agger entrega extrato e parcelas; fica para depois.
- Integração direta com seguradoras. Só pelo robô do Agger.
- Outros sistemas de gestão (Quiver, Segfy). O bundle do Agger cita Quiver Plus/Pro; não pesquisado.

**Anti-metas (falharia mesmo funcionando)**
- Virar sistema de gestão de corretora (brigar com Segfy/ONE em comissão e multicálculo).
- Encher o kanban com centenas de cards que vencem daqui a meses.
- Pegar o telefone errado do PDF (SAC da seguradora, corretor) e mandar WhatsApp para quem não é o segurado.
- Gastar consulta paga do Agger cotando a carteira inteira de uma vez.
- Interpretar texto com regex ou lista de palavras (regra do Rodrigo de 20/09).

## 3. Decisões do Rodrigo (11/11/2026)

1. **A apólice tem tabela própria**, com o PDF guardado ("excelência máxima"). Não é campo do contato nem card ganho.
2. **O card só nasce perto do vencimento.** Até lá a apólice vive na tabela e aparece na ficha.
3. **O cliente vem da apólice, não do funil.** Ao importar, o contato vira cliente desde o início da vigência.
   Qualquer funil serve para a renovação, inclusive de Atender, que é muito usado para atender clientes.
   Hoje `ContactCustomer#become_customer!` não recebe data (grava `Time.current` na primeira vez). A extensão
   `become_customer!(since:)` já foi combinada com a sessão Multifunil em 11/10: a data mais antiga vence, atualiza
   quem já é cliente, mantém o lock e o `save!(validate: false)`.
4. **A corretora escolhe onde ficam as renovações**: criar o funil Renovação pelo modelo pronto do nicho, ou escolher
   um funil e etapa existentes. Escolhe também quantos dias antes o card aparece.
5. **Agger:** a carteira usa a mesma conexão da Lia (`Autonomia::Insurance::Connection`), mas a **cotação de
   renovação tem chave própria**, separada da importação, porque pode ser vendida como upgrade.
6. **Telefone do PDF:** achar a página do segurado por um dado conhecido e só ela vai ao modelo (detalhe em §6.4).
7. **Planilha:** a ficha da apólice tem "Anexar PDF"; ao anexar, os campos do PDF conferem os da planilha.
8. **Faltou dado para cotar:** se a conta tem a Lia, a Lia pergunta ao segurado; se não tem agente, avisa a equipe.
   O Rodrigo espera que falte pouco: as regras da Lia exigem apólice completa.
9. **PDF ou planilha (sem Agger):** sem cotação automática; chega notificação conforme as regras escolhidas.

## 4. O que já existe e é reaproveitado

| Peça | Onde |
|---|---|
| Leitura de planilha com IA (Jev), telefone BR, tipo de coluna | `app/services/campaign_imports/` (`spreadsheet_reader.rb`, `column_types.rb`, `contact_reading.rb`), flag `customer_base` |
| Contato cliente com data | `app/models/concerns/contact_customer.rb` |
| Opt-out com origem | `app/models/concerns/contact_opt_out.rb` |
| Modelo do funil Renovação (Vender): A vencer, Cotando, Opções enviadas, Negociação, Renovado; desfechos Renovou / Não renovou | `crm/components/funil/funil.js:115`, `CRM_FUNIL.MODELOS.RENOVACAO` em `crm.json`, `Crm::Pipeline::TEMPLATES` |
| Desfecho por tipo de funil (won/lost x resolved/cancelled) | `app/services/crm/cards/outcome.rb` |
| Gatilho por data em card e contato | `app/services/autonomia/automacao/tempo/data.rb`, `gatilhos.rb` |
| Mensagem por modelo do WhatsApp na automação | `automacao/campanha_da_execucao.rb` |
| Leitor de PDF com OCR local (tesseract) | `app/services/autonomia/agents/knowledge/processors/pdf.rb`, `pdf_ocr.rb` |
| Conexão Agger, cotação, `quote_validate`, renovação no auto e nos ramos | `app/services/autonomia/insurance/connector/http.rb`, `auto_renewal.rb`, `entrada_da_cotacao.rb:82` |
| Mídias do relacionamento no card | `CRM_*.MEDIA` em `crm.json` ("Mídias do relacionamento") |

## 5. Dados novos

Tabelas do fork, só aditivas. Nomes e colunas finais ficam com o construtor; o conteúdo mínimo é este.

**Apólice** (uma linha por apólice/endosso vigente)
- conta, contato, empresa (quando CNPJ), lote de importação, origem (`agger`, `pdf`, `planilha`), id na origem
  (o `id` do documento no Agger, para não duplicar);
- número, endosso, proposta, ramo, seguradora, início e fim da vigência, data de emissão, prêmio líquido e total;
- situação: ativa, renovada, não renovada, cancelada;
- apólice anterior (a que esta renovou);
- campos que vieram com dúvida (para a tela mostrar "conferir").

**PDF da apólice** guardado conosco (ActiveStorage), não só o link da origem.

**Parcelas e item segurado** (endereço do imóvel, por exemplo): o Agger entrega; guardar em tabelas filhas ou num
campo estruturado é escolha do construtor. Não são exibidos na primeira entrega.

**Configuração de renovação por conta**: funil, etapa de entrada, dias antes do vencimento, quem cota, quem envia
(§7). Uma por conta na primeira entrega.

**Mesma apólice, endosso e conflito entre origens** (escolha minha, a conferir):
- mesma apólice = mesma seguradora + mesmo número (só dígitos), em qualquer origem;
- endosso **atualiza** a apólice (vigência, prêmio, item) e fica no histórico dela; nunca vira linha nova nem card novo;
- precedência: Agger > PDF > planilha; campo editado por pessoa nunca é sobrescrito pela sincronização.

**CPF/CNPJ do segurado** (escolha minha, a conferir): guardado na apólice, criptografado (Active Record Encryption),
não no contato. É por ele que apólices da mesma pessoa se juntam e que o contato é casado. Telefone do PDF que já
pertence a outro contato (outro nome ou outro CPF) **não** liga sozinho: vai para o Conferir como conflito. Nunca vai
para log, Step Summary ou issue (o repositório é público).

**Ramo e seguradora** são códigos. O Agger usa códigos próprios e o PDF traz outros. O mapa de códigos já existe no
repo `autonomia-adapters` (`src/platforms/agger/knowledge/`); planilha e PDF trazem nomes. A apólice guarda código e nome.

## 6. As três entradas

Todas começam em Relacionamentos → **Trazer minha carteira** (rota filha de Relacionamentos, sem item novo no menu,
como decidido em 15/10). Todas terminam em **Conferir → Confirmar**, com desfazer por 7 dias (PRD-F1, D6).

**Passo único na primeira importação: "Onde ficam as renovações?"**
- **Criar o funil Renovação** (modelo pronto do nicho; o card entra em "A vencer"), ou
- **Usar um funil que já tenho**: escolhe funil **e** etapa, de qualquer tipo.
- **Quantos dias antes** o card aparece (padrão 60).

### 6.1 Pelo Agger

1. Escolhe **Pelo Agger**. Sem conexão, conecta com o login da corretora (a mesma conexão da Lia).
2. Passo único das renovações.
3. O chat2you pede a sincronização ao robô do Agger e acompanha a fila sozinho. Medido em 11/11 numa conta de corretora de teste
   (chamadas e formatos no repositório privado `autonomia-adapters`, `docs/agger/carteira-apolices.md`):
   - o módulo de apólices é por permissão contratada no Agger;
   - o Agger só cria pedido para seguradora em que a corretora guardou a senha (no teste: 4 de 13);
   - os pedidos ficaram 12 min pendentes no teste;
   - a leitura vem 20 por página.
4. Para cada apólice: grava, baixa o PDF, acha telefone e e-mail (§6.4), casa ou cria o contato, cria a empresa
   quando CNPJ, marca cliente desde o início da vigência.
5. Conferir: "312 apólices · 280 pessoas · 24 sem telefone", fichas de exemplo mascaradas, problemas com ação. Aviso
   por seguradora sem senha no Agger ("Faltou a senha da Porto no Agger").
6. Depois: sincronização diária sozinha (apólice nova, endosso, renovação feita fora).

Período (escolha minha, a conferir): a primeira sincronização pede os últimos 12 meses de emissão, mês a mês (uma
apólice anual vigente foi emitida nesse período); as diárias pedem os últimos 7 dias.

Onde mora o código do Agger: no repositório `autonomia-adapters` (Lambda), como a cotação. O `connector/http.rb` do
chat2you não conhece endpoint nem formato do portal; ganha operações novas (pedir sincronização, ler pedidos, ler
apólices, baixar PDF) e o adapter as implementa. Esse trabalho faz parte do épico.

O que o Agger devolve por apólice (medido): número, proposta, endosso, ramo, seguradora, início e fim da vigência,
emissão, prêmio líquido e total, segurado (nome, CPF/CNPJ, e-mail), endereço do item, parcelas e o PDF. Há um segundo
formato, vindo da fila do robô, que **não traz CPF/CNPJ**. Nenhum dos dois traz **telefone**; o PDF traz.

### 6.2 Por PDFs

1. Escolhe **Tenho os PDFs** e arrasta vários arquivos.
2. Passo único das renovações.
3. Para cada PDF: lê o texto (OCR local só se for imagem), o modelo barato extrai os campos da apólice, cada um com
   "não achei"; casa o contato e marca cliente como em 6.1.
4. Custo: o modelo roda em todo PDF (layout muda por seguradora), mas só sobre as páginas escolhidas. Medir numa
   bateria antes de ligar; mostrar estimativa antes de começar; teto por conta.
5. Conferir: campo em dúvida chega aberto ("Não achei o fim da vigência neste PDF").

### 6.3 Por planilha

1. Escolhe **Tenho uma planilha**.
2. O Jev lê as colunas como na F0 e pergunta **"Esta planilha tem seguros?"**; mapeia número, ramo, seguradora e fim
   da vigência (obrigatórios para renovar). Pessoa em várias linhas = um contato com várias apólices.
3. Passo único das renovações. Conferir e confirmar.
4. Sem PDF. A ficha da apólice tem **Anexar PDF**; ao anexar, os campos do PDF conferem os da planilha e apontam
   diferença.

### 6.4 Telefone e e-mail do segurado no PDF

Medido em 11/11 com 3 PDFs reais: uma apólice empresarial tem 161 páginas, o CNPJ do segurado aparece nas páginas 1 e 160 e a
palavra "fone" em 12 páginas (SAC, assistência, ouvidoria). Posição fixa e rótulo não servem.

1. Achar a página do segurado por um dado que já conhecemos: o CPF/CNPJ da origem, comparando só os dígitos;
   sem ele, o nome do segurado; sem nenhum, as primeiras páginas (cobre a capa). É comparação de valor exato, não
   interpretação de texto.
2. Só essas páginas vão ao modelo barato: "telefone e e-mail do **segurado**", com "não achei".
3. Página sem texto: OCR local só dela.
4. Sem telefone: o contato entra marcado "sem telefone" e é casado depois por CPF/CNPJ.
5. Antes de ligar: bateria com PDFs de várias seguradoras, como a F0 das planilhas.

## 7. Da importação até "Renovou"

**Durante a vigência.** A ficha do contato mostra **Seguros**: "Empresarial · Seguradora Exemplo · vence 10/03/2027 · PDF".
Relacionamentos filtra por ramo, seguradora e vencimento.

**N dias antes (padrão D-60).** A rotina diária cria o card no funil e etapa escolhidos, ligado à apólice, com os dados
e o PDF à vista.

**Cotando.** Três escolhas independentes por conta:

| Escolha | Opções |
|---|---|
| Quem cota | o **robô de renovação** (adapter do Agger, sem IA de conversa) · a **Lia** · ninguém |
| Quem envia a proposta | a **campanha** (modelo do WhatsApp) · uma **pessoa** (proposta nas mídias do card) |
| Quem responde o segurado | a **Lia** · a **equipe** |

- Origem Agger + chave de cotação liberada: o robô ou a Lia cota a renovação a partir da apólice anterior (número,
  seguradora e vigência entram no grupo "renovação" da cotação).
- Sem a Lia: o robô cota; a campanha manda a proposta ou ela fica no card para alguém enviar.
- Com a Lia: ela cota, o disparo leva a proposta e ela conversa depois.
- Antes de gastar a consulta paga, conferir a entrada com `quote_validate`. Faltou dado: com a Lia, ela pergunta ao
  segurado; sem agente, avisa a equipe.
- Cotar só o card que chegou na etapa de entrada, com teto mensal por conta (cotação no Agger consome consulta paga).
- Origem PDF ou planilha: sem cotação automática; notificação conforme as regras.

**Envio pelo WhatsApp.** Fora da janela de 24 h só com modelo aprovado pela Meta. Quem pediu para parar não recebe.
Conferir categoria e layout do modelo com PDF (já vimos PDF sem miniatura na Cloud API).

**Renovou.** O card fecha ganho. A apólice antiga vira "renovada". A nova: pelo Agger, chega na próxima sincronização e
se liga à anterior; nos outros casos, o card pede "Anexar a apólice nova (PDF)". O ciclo recomeça.

**Não renovou.** O card fecha perdido; a apólice vira "não renovada" no fim da vigência.

## 8. Riscos

- **API interna do Agger**, não pública: pode mudar sem aviso (já mudou de host em 10/2026). Isolar no repo de
  adapters, como a cotação.
- **Robô do Agger lento**: no teste os pedidos ficaram 12 min pendentes. A tela não pode prometer tempo.
- **Dado de cliente da corretora** lido com o login dela: a corretora autoriza ao conectar.
- **Custo** de IA por PDF e de consulta paga de cotação: medir e pôr teto antes de ligar.
- **Kanban cheio** se os dias antes forem grandes demais numa carteira grande.

## 8.1 Respostas do Rodrigo (11/11/2026, tarde) — valem sobre o texto acima

O plano do épico está em `PLANO-EPICO.html`, nesta pasta. Onde este desenho divergir do plano, vale o plano.

1. **Primeira importação:** nada vira card na hora. A rotina diária cria o card quando a apólice entra nos N dias antes
   do vencimento (as que já estão na janela viram card na manhã seguinte). Vencida entra sem card.
2. **Um card por apólice.** A mesma pessoa pode ter auto, empresarial, residencial, vida.
3. **Sempre cliente.** Não existe "ex-cliente". Cada apólice tem um selo calculado pela data de hoje: Ativo, Em
   renovação, Renovado, Vencido, Cancelado. Na lista, o contato mostra o selo mais urgente.
4. **Notificação de PDF/planilha:** para a equipe.
5. **Chave da cotação de renovação:** no Super Admin, por conta.
6. **Reformulação de Relacionamentos:** entra neste épico.
7. **Mesma apólice e endosso (§5):** aprovado como escrito.
8. **CPF/CNPJ (§5): recusado como escrito.** O dado é do negócio e precisa estar à mão para cotar. Fica na ficha do
   contato (e CNPJ na empresa), visível para a equipe e usado pela cotação e pelos agentes; protegido no banco e fora
   de log, sem travar a operação. Conflito de telefone não bloqueia a importação: o sistema casa pelo CPF/CNPJ e segue.
9. **Período do Agger (§6.1):** primeira sincronização pede 36 meses (pega plurianual); as diárias, 7 dias.
10. **Sem teto de uso.** O "teto mensal por conta" da cotação (§2, §6.2, §7) cai: regra de 31/10 ("não coloque freio
    em humano"). Fica custo à vista e a escolha da própria corretora.
11. **Mockups:** avaliados por outros chats do projeto contra a regra de ouro, não pelo Rodrigo.

## 9. Aberto com o Rodrigo (em 11/11, antes de planejar) — RESPONDIDO em §8.1

Vieram da revisão de um construtor independente (11/11) e da conversa. Em ordem de impacto:

1. **Primeira importação com apólices já dentro da janela ou vencidas.** Recomendação: as que vencem dentro da janela
   viram card na hora, com cotação respeitando o teto mensal; as já vencidas entram como "vencida, sem renovação
   registrada", sem card. Alternativas: a corretora escolhe no Conferir; ou esperar a rotina diária.
2. **Um card por apólice ou por pessoa** (auto e residencial vencendo no mesmo mês). Recomendação: um por apólice.
3. Não renovou e não tem outra apólice ativa: continua **cliente** ou passa a **ex-cliente**?
4. A notificação de PDF/planilha (§3.9) é para a equipe? (Palpite: sim.)
5. A chave da cotação de renovação fica no Super Admin, por conta, como os ramos da Lia? (Palpite: sim.)
6. Reformulação de Relacionamentos (lista, grupos prontos, ficha): entra neste épico ou é a fase seguinte do PRD-F1?

Escolhas minhas marcadas no texto como "a conferir": mesma apólice e endosso (§5), CPF/CNPJ na apólice (§5), período e
lugar do código do Agger (§6.1).

## 9.1 Estado em 11/11/2026

- Este documento: worktree `/Users/rodrigosilva/dev/worktrees/chat2you/1240-carteira-seguros`, branch
  `docs/1240-carteira-seguros` (de origin/main), **sem commit**. Sem Issue própria ainda; usar `Refs #1240`.
- Repositório chat é **público**: endpoints e formatos do Agger ficam só no `autonomia-adapters` (privado).
- PR #1321 (pesquisa, dados de produção e PRD-F1) segue aberto esperando OK de merge.
- Código: nenhum. Próximo passo depois das respostas: plano de implementação.

## 10. Deixado ao construtor

Nomes de tabela e coluna; tabelas filhas ou campo estruturado para parcelas e itens; como a rotina diária e a
sincronização se agendam; mapa de códigos de ramo e seguradora; ordem das entregas (sugestão: tabela + planilha →
ficha → Agger → renovação → PDF → cotação).

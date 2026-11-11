# Dados de produção: Relacionamentos e Base de clientes

Medição de 11/10/2026, nas duas instalações (Hub2You e Autonom.ia), em todas as contas ativas. Épico #1240.

**Como foi medido.** Consulta só de leitura, em 5 partes, rodada pela Orquestração fora de deploy (SQL e regras em [`consulta-producao/`](consulta-producao/LEIA-ME.md)). Saem só contagens: nenhum nome, telefone, e-mail, conteúdo ou valor de campo. Texto (nome de campo, título de coluna) só sai quando aparece em 3 ou mais contas. Este documento também não identifica contas: elas aparecem agrupadas por tipo.

---

## 1. O retrato

| | Hub2You | Autonom.ia |
|---|---|---|
| Contas ativas | 14, mais 1 conta de teste fora dos números | 7 (2 sem contato) |
| Contatos | 13.870 (mediana de cerca de 1.300 por conta, máximo 3.047) | 637 (mediana 8, máximo 400) |
| Com telefone | 98,3% | 92,2% |
| Com e-mail | **1,0%** (145) | 1,9% (12) |
| Nunca tiveram conversa | **55,0%** (7.629) | 24,6% |
| Marcados como cliente (`contact_type = customer`) | **4** (0,03%) | 0 |
| Com negócio (card) | 20% | 72% |
| Negócios ganhos | 70 de 3.098 | 0 de 477 |
| Empresas cadastradas | 91, em 5 contas | 13, em 1 conta |
| Campos de contato criados por pessoas (fora os de sistema) | 4, todos na conta do piloto | 16, em 3 contas |
| Importações pela planilha nova | 2 (testes do piloto) | 0 |

A plataforma é nova: o contato mais antigo é de junho/2026, e nenhum ficou mais de 6 meses sem escrever porque ainda não houve tempo para isso.

**Conta de teste.** Uma conta ativa da Hub2You é de teste, como o Rodrigo confirmou: 752 contatos sem telefone, e-mail nem canal, criados num dia de junho, com 55 chaves de campo sem definição. Ela ficou fora dos números da Hub2You neste documento. A consulta a inclui, porque a conta está ativa; ao repetir, desconte-a.

### Tipos de conta (Hub2You)

| Tipo | Contas | Contatos | Como o contato chegou | O que o caracteriza |
|---|---|---|---|---|
| **Agenda do WhatsApp sincronizada** | 4 | 6.328 | 1.300 a 1.700 contatos num dia só, na conexão da Coexistência | 68% a 99% nunca conversaram; `last_activity_at` falha (seção 2.6) |
| **Atendimento ativo** | 4 | 6.007 | Pela conversa, todo dia | Negócio criado sozinho pela conversa; uma delas tem exatamente 1 negócio por contato |
| **Base que chegou de fora** | 1 | 1.333 | Num dia só, sem caixa de entrada | 96% sem conversa |
| **Pequenas ou de teste** | 5 | 202 | Variado | Inclui a conta do piloto |

---

## 2. Achados e o que mudam no produto

### 2.1 A pessoa é o telefone, e 23% dos telefones estão sem o nono dígito
- 98% dos contatos têm telefone e só 1% tem e-mail. Lista, busca e ficha giram em torno do telefone.
- 76,7% dos telefones são celular brasileiro completo e **22,9% têm 12 dígitos** (55 + DDD + 8): fixo ou celular sem o nono dígito (a consulta não separou os dois). Varia muito por conta, de 0% a 95%, e passa de 30% em 5 contas.
- Duplicado hoje é raro: 9 pares em 13.870, 8 deles só pela diferença do nono dígito. O `rake contacts:merge_ninth_digit_duplicates` (#990) já limpou o resto.
- **Implicação para a Base de clientes:** a planilha chega com o 9 (o motor da F0 completa o nono dígito). Se a F1 comparar o número exato, cada celular salvo sem o 9 vira um contato novo. **A F1 precisa casar o telefone com e sem o nono dígito**, como faz o bloco 6 (`pares_ignorando_nono_digito`). É o maior risco da ferramenta.

### 2.2 "Cliente" quase não existe nos dados
- 99,5% dos contatos são `lead`, 0,5% `visitor` e só 4 são `customer`, todos marcados em outubro numa só conta.
- Dos 40 contatos com negócio ganho, 36 não estão marcados como cliente.
- **Implicação:**
  - "Contatos" continua sendo o nome de todo mundo, e "cliente" vira um estado: quem comprou.
  - A Base de clientes é a primeira fonte real desse estado. A pergunta "Essas pessoas já são clientes?" na importação, com `customer_since`, preenche um campo que hoje está vazio.
  - Vale decidir se negócio ganho deve marcar o contato como cliente (`ContactCustomer`, #1144). Os 36 de hoje mostram que isso não acontece.

### 2.3 Empresas: o backfill não resolve, porque o dado não existe
- 91 empresas na Hub2You, quase todas (87) só com nome e domínio, o formato da associação automática por e-mail. Nenhuma com CNPJ, nenhuma da Prospecção.
- Menos de 1% dos contatos está ligado a uma empresa (118) ou tem o texto `company_name` (126).
- Simulação do que já existe no código:
  - **backfill por domínio do e-mail** (`rake companies:backfill`): criaria cerca de 11 empresas na Hub2You;
  - **backfill pelo `company_name`:** 8 na Hub2You e 49 numa conta da Autonom.ia, a que usa Prospecção.
- O medo da "empresa de provedor grátis" (`hotmail.com.br` e outros que faltam na lista da gem) é real no código, mas **quase nulo hoje**: quase ninguém tem e-mail. Vira risco quando a planilha trouxer e-mail em volume, então a lista precisa ser corrigida antes disso.
- **Implicação para a decisão D1** (empresa como destino na v1):
  - Empresa vai nascer da planilha (coluna empresa e CNPJ), da Prospecção e da IA lendo a conversa, não de backfill.
  - Na maioria das contas, a aba Empresas começa vazia. A tela tem que funcionar bem sem empresa e não pode empurrar o usuário para ela.
  - A flag `companies` está ligada nas 15 contas da Hub2You.

### 2.4 A aba Informações está vazia para quase todo mundo
- Das 29 definições de campo da Hub2You, 21 são chaves de sistema da integração WAHA (`waha_whatsapp_chat_id`, `_jid` e `_lid`, em 7 contas). O resto: 3 campos de conversa em 2 contas, 1 de empresa e 4 de contato, todos esses 5 na conta do piloto. Dos 4 de contato, 3 estão **sem descrição**: vieram do teste da importação (#1006 cria campo sem descrição). É o problema que o Rodrigo levantou, agora confirmado com dado.
- Na Autonom.ia, uma conta usa de verdade: a maior parte dos 16 campos de contato e dos 26 de conversa da instalação está nela.
- Nenhum negócio tem campo personalizado preenchido, nas duas instalações.
- `additional_attributes` só tem chave de sistema: avatar, `source_id`, Instagram (29 contatos), `company_name` (126). Cidade e país praticamente não aparecem.
- **Implicação:**
  - A Base de clientes vai ser a primeira fonte de informação sobre a pessoa, a empresa e o negócio. Criar o campo com **nome e "Para que serve?"** é obrigatório, porque é o que a IA do CRM lê.
  - A ficha não deve mostrar chave técnica (`waha_*`) para o usuário.

### 2.5 A maior parte da base nunca conversou
- 55% dos contatos da Hub2You nunca tiveram conversa, e 60% nunca escreveram. 84% desses sem conversa estão nas contas de agenda sincronizada e na base que chegou de fora.
- Só 0,1% (12 pessoas) aparece em mais de um tipo de canal, e 85% de quem conversou teve uma conversa só (p90 = 2).
- **Implicação para a lista e os grupos (LG):**
  - A lista precisa separar quem conversou de quem só está na agenda, e "Nunca conversou" é um grupo pronto necessário.
  - A Base de clientes vai aumentar esse grupo, porque traz gente que ainda não falou com a empresa.
  - Juntar a mesma pessoa de canais diferentes não é prioridade de v1.
  - A ficha não precisa de linha do tempo com muitas conversas na v1.

### 2.6 `last_activity_at` falha nas contas da Coexistência
- Dos 4.817 contatos que escreveram nos últimos 90 dias (Hub2You), 92,7% têm o campo certo. **340 (7,1%) estão com ele vazio, 339 deles nas 4 contas de agenda sincronizada**, onde a falha atinge de 37% a 82% de quem escreveu. Na Autonom.ia, 100% batem.
- **Causa:** as mensagens de histórico da Coexistência entram com a data original (`app/services/whatsapp/history_message_service.rb:9`), mas são marcadas `history_import` e pulam a atualização da atividade do contato (`app/models/message.rb:337`). A pessoa escreveu de verdade, e o campo diz que nunca.
- **Implicação:** antes de construir "Falou com você há pouco" e "Sumiu há…", corrigir na causa. A importação do histórico deve levar o `last_activity_at` à data da mensagem do contato, sem os outros efeitos de mensagem nova. Os contatos que já existem precisam de um backfill único a partir das mensagens.

### 2.7 Etiqueta não é o jeito de segmentar
- Só 1 conta usa etiqueta: 41 etiquetas, em 53% dos contatos dela. Nas outras 14 da Hub2You, zero. Na Autonom.ia, 2 etiquetas em 24 contatos.
- **Implicação:** os grupos prontos não podem depender de etiqueta. Etiqueta fica como filtro opcional.

### 2.8 Negócios nascem da conversa e não têm dado próprio
- 94% dos negócios da Hub2You nasceram de uma conversa de WhatsApp (a origem gravada é o canal da conversa; 10 contas têm caixa que cria negócio sozinha). 28% têm valor e nenhum tem campo personalizado. Metade dos abertos está parada há mais de 30 dias.
- Na Autonom.ia, 35 negócios vieram da Prospecção, e 38 têm `external_id`.
- **Implicação para a D2** (criar negócio na importação): as colunas de negócio da planilha vão ser os primeiros campos de card da plataforma. A ficha da pessoa mostra os negócios dela, já que 20% dos contatos têm um.

### 2.9 Ninguém usou a importação nova ainda
- Na Hub2You: as 2 importações de teste do piloto e 13 importações antigas de campanha numa só conta. Na Autonom.ia, nenhuma.
- Nenhum título de coluna de planilha aparece em 3 contas.
- **Implicação:** não há vocabulário real de planilha em produção. A bateria de 62 planilhas da F0 continua sendo a única base. O piloto da conta 16 vai gerar o primeiro dado real; repetir esta consulta depois do piloto mede a adoção.

---

## 3. O que esta medição não cobre

- **Importação nativa de CSV do Chatwoot** (`data_imports`): não foi medida. É o caminho provável da "base que chegou de fora".
- **Origem de cada contato:** a plataforma não grava se o contato veio da conversa, da agenda, da API ou de planilha. Os tipos da seção 1 foram inferidos pelo ritmo de criação e pela existência de conversa. A Base de clientes deve gravar o lote de origem, que também serve para o "desfazer importação".
- **Conversas de histórico:** o bloco 42 usa `conversations.last_activity_at`. A conversa criada pelo histórico também tem guarda de `history_import` (`app/models/conversation.rb:373`) e não foi conferida aqui.

---

## 4. Próximos passos sugeridos

1. **F1, telefone:** casar com e sem o nono dígito na importação. Bloqueia a F1.
2. **Atividade:** corrigir `last_activity_at` nas mensagens de histórico da Coexistência e fazer backfill. Bloqueia os grupos prontos.
3. **Termos:** "Contatos" como nome geral; "cliente" como estado (quem comprou), marcado pela importação e, se decidido, pelo negócio ganho.
4. **Empresas:** corrigir a lista de e-mail grátis antes de importar e-mail em volume. Não rodar o backfill por domínio esperando volume, porque ele traria cerca de 11 empresas.
5. **Conta de teste:** confirmada pelo Rodrigo. Descontar ao repetir a consulta.
6. **Repetir esta consulta** depois do piloto da Base de clientes.

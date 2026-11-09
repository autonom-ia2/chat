# Protótipo #1430 — "Gerenciar ferramentas" para a equipe (PR2a)

Tela real do painel, rodando na demo local (`bin/demo`, slug `1430-ferramentas`), com as flags de produção e a flag
`agente_ferramentas_delegadas` ligada. Prints em 1440 px e 390 px nesta pasta (`prints/`).

## O que muda para quem usa

Hoje só a equipe da plataforma cria ferramentas dos agentes. Com a flag ligada na conta:

- **O administrador** cria ferramentas, como hoje faz a plataforma.
- **O administrador entrega** a outras pessoas a área "Ferramentas dos agentes" na função delas. Quem não é
  administrador vê essa área com cadeado: a chave é de delegação.
- **Quem recebe** abre Mais opções › Ferramentas dos agentes na página do agente, mesmo sem poder editar o agente, e cria, testa e
  liga a ferramenta. A Lia (cotação) fica de fora.

## Jornada 1 — o administrador libera (`prints/1-admin-libera`)

1. Funções da equipe › Alterar "Supervisão".
2. Abre "mais 15 áreas". A área nova fica logo depois de "Robôs de IA", com o aviso: *"Quem tem isto escolhe para onde
   vão os dados das conversas. Só o administrador libera."*
3. Escolhe "Pode mexer". A linha sobe com "você mudou", e "Como vai ficar" ganha *"Criar e ligar as ferramentas
   dos agentes"* com o selo "novo".
4. Confira. O menu continua "Conversas e Robôs de IA": a área não abre item novo, porque as ferramentas moram na
   página do agente.

## Jornada 2 — a Paula cria e testa (`prints/2-paula-cria-e-testa-1440` e `-390`)

A Paula tem a função "Sistemas": vê os agentes e tem a chave, mas não edita o agente.

1. Página da Ana. A faixa diz *"Você pode ver, testar e cuidar das ferramentas. O resto fica com quem administra a
   conta."*
2. Mais opções › Ferramentas dos agentes. Lista vazia, com uma frase e um botão.
3. Passo 1, o que ela faz: nome e quando usar.
4. Passo 2, o que o agente descobre: uma informação chamada **CEP**, com nome de gente.
5. Passo 3, onde buscar: "Buscar informação" ou "Mandar informação"; cola o link que o outro sistema deu
   (`https://viacep.com.br/ws//json/`), deixa o cursor no lugar e toca no botão **CEP**. O próprio campo passa a
   mostrar `https://viacep.com.br/ws/[CEP]/json/`; só o que é salvo leva `{{cep}}`. Ela nunca digita nem vê chaves. Link
   colado com `{{x}}` aparece como `[x]`; colchete que já é do link (`filter[status]`) fica como está.
6. Passo 4, chave de acesso (se o sistema pedir). O ViaCEP não pede.
7. Teste com o CEP 01001000: "Deu certo", e o que o agente recebe em linhas (Cep, Logradouro, Bairro, Localidade…).
   O que foi para o outro sistema e a resposta completa ficam em "Ver detalhes".
8. Ligar ferramenta.

## Linguagem (decisão do Rodrigo, 09/11: "1A 2 recomendado")

- Fora da tela que a pessoa percorre: GET/POST, corpo, cabeçalho, Content-Type/Accept, JSON e chaves duplas. Um teste
  (`linguagemDasFerramentas.spec.js`) trava a volta dessas palavras nos passos e no teste.
- Nome técnico, o formato do que vai junto (já pronto com as informações do passo 2) e o recorte da resposta ficam em
  "Avançado", no passo 3.
- Cada informação tem o nome de gente ("CEP") guardado como `label`; o nome técnico sai dele e não aparece. Numa
  ferramenta salva, o técnico fica fixo, para o link montado não quebrar. O `label` nunca vai ao modelo.
- O nome dos campos na resposta do teste vem do próprio sistema ("Logradouro", "Localidade"): não há tradução de
  palavra para palavra.

## Achados que o protótipo pegou (já corrigidos no PR2a)

1. **A tela de Funções em produção é a guiada** (`funcoes_guiadas`, ligada em todas as contas). O PR2a só tinha mexido
   na tela antiga. A área entrou no mapa fechado da guiada (25 áreas, 60 chaves), com o filtro da flag, o cadeado, o
   "Pode" e o menu.
2. **Endereço com `{{variável}}` não salvava** (defeito que já está na main, do PR1). O cadastro validava o endereço
   com as chaves, que não é um endereço válido, e respondia "Endpoint url inválida". Agora valida como a chamada é
   feita, com cada `{{ }}` vazio, e a mensagem diz "Endereço não é válido".
3. **Textos que diziam "só a equipe da plataforma"** agora apontam a permissão e o administrador.

## Decidido

1. Jargão: sai dentro do PR2a (acima).
2. Nome da área: "Ferramentas dos agentes" na função e na página do agente.

## Como reproduzir

```sh
bin/demo up 1430-ferramentas
bin/demo seed 1430-ferramentas docs/audit/2026-11-08-1430-prototipo/seed_demo.rb
bin/demo prints 1430-ferramentas docs/audit/2026-11-08-1430-prototipo/jornada-admin.json
bin/demo prints 1430-ferramentas docs/audit/2026-11-08-1430-prototipo/jornada-paula-1440.json
```

Entre as jornadas da Paula, apague a ferramenta criada (`bin/demo psql 1430-ferramentas "DELETE FROM
autonomia_agent_tools"`), senão o nome repete. O kit da demo não liga o módulo de Agentes sozinho: nesta demo foi
passado `AUTONOMIA_AGENTS_ENABLED=true` só no ambiente dela, fora do commit.

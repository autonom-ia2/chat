# Protótipo #1430 — "Gerenciar ferramentas" para a equipe (PR2a)

Tela real do painel, rodando na demo local (`bin/demo`, slug `1430-ferramentas`), com as flags de produção e a flag
`agente_ferramentas_delegadas` ligada. Prints em 1440 px e 390 px nesta pasta (`prints/`).

## O que muda para quem usa

Hoje só a equipe da plataforma cria ferramentas dos agentes. Com a flag ligada na conta:

- **O administrador** cria ferramentas, como hoje faz a plataforma.
- **O administrador entrega** a outras pessoas a área "Robôs ligados a outros sistemas" na função delas. Quem não é
  administrador vê essa área com cadeado: a chave é de delegação.
- **Quem recebe** abre Mais opções › Ferramentas na página do agente, mesmo sem poder editar o agente, e cria, testa e
  liga a ferramenta. A Lia (cotação) fica de fora.

## Jornada 1 — o administrador libera (`prints/1-admin-libera`)

1. Funções da equipe › Alterar "Supervisão".
2. Abre "mais 15 áreas". A área nova fica logo depois de "Robôs de IA", com o aviso: *"Quem tem isto escolhe para onde
   vão os dados das conversas. Só o administrador libera."*
3. Escolhe "Pode mexer". A linha sobe com "você mudou", e "Como vai ficar" ganha *"Ligar os robôs de IA a outros
   sistemas da empresa"* com o selo "novo".
4. Confira. O menu continua "Conversas e Robôs de IA": a área não abre item novo, porque as ferramentas moram na
   página do agente.

## Jornada 2 — a Paula cria e testa (`prints/2-paula-cria-e-testa-1440` e `-390`)

A Paula tem a função "Sistemas": vê os agentes e tem a chave, mas não edita o agente.

1. Página da Ana. A faixa diz *"Você pode ver, testar e cuidar das ferramentas. O resto fica com quem administra a
   conta."*
2. Mais opções › Ferramentas. Lista vazia, com uma frase e um botão.
3. Os 4 passos do cadastro, com uma ferramenta de exemplo que todo mundo entende: **endereço pelo CEP**
   (`https://viacep.com.br/ws/{{cep}}/json/`).
4. Teste com o CEP 01001000: "Deu certo", e o que o agente recebe (rua, bairro, cidade).
5. Ligar ferramenta.

## Achados que o protótipo pegou (já corrigidos no PR2a)

1. **A tela de Funções em produção é a guiada** (`funcoes_guiadas`, ligada em todas as contas). O PR2a só tinha mexido
   na tela antiga. A área entrou no mapa fechado da guiada (25 áreas, 60 chaves), com o filtro da flag, o cadeado, o
   "Pode" e o menu.
2. **Endereço com `{{variável}}` não salvava** (defeito que já está na main, do PR1). O cadastro validava o endereço
   com as chaves, que não é um endereço válido, e respondia "Endpoint url inválida". Agora valida como a chamada é
   feita, com cada `{{ }}` vazio, e a mensagem diz "Endereço não é válido".
3. **Textos que diziam "só a equipe da plataforma"** agora apontam a permissão e o administrador.

## Para o Rodrigo decidir

1. **Jargão no cadastro da ferramenta.** O assistente (feito no PR1 para a equipe da plataforma) ainda mostra "Só buscar
   (GET)", "Enviar dados (POST)", "Nome técnico", "Corpo da chamada… em JSON", "cabeçalho", "Content-Type" e
   "mapeamento", e o exemplo do passo 3 usa `{{termo}}`. Quem liga o agente a outro sistema precisa do endereço e da
   chave que esse sistema dá; mas a regra de ouro pede tela sem jargão.
   - **A (recomendo):** PR2a sai com o assistente como está e abrimos uma Issue de linguagem: GET/POST viram só "Buscar
     um dado" / "Enviar dados"; "Nome técnico", corpo, cabeçalho e mapeamento vão para "Avançado"; a chave vira
     "Chave de acesso que o sistema te deu". Não atrasa a entrega da permissão.
   - **B:** fazer a revisão de linguagem dentro do PR2a, com novo protótipo antes do PR.
2. **Nome da área na função:** "Robôs ligados a outros sistemas" (segue "Robôs de IA" da tela guiada). Na tela antiga
   ela se chama "Ferramentas dos agentes", e no agente o menu diz "Ferramentas". Manter assim, ou "Ferramentas dos
   robôs" nos dois lugares?

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

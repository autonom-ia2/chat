# Pedido de acesso ao "Sign in with ChatGPT" (SIWC): pacote para o Rodrigo

Épico: autonom-ia2/chat#2472. Preparado em 02/11/2026.

## Por que precisa do formulário

A OpenAI só libera o login ChatGPT com uso do plano para **app pago ou hospedado** por convite. A doc diz: "If you're interested in offering it in a paid or remotely hosted app, complete the interest form" (developers.openai.com/siwc/token-sharing-open-source). Para site, o programa está em teste com parceiros selecionados: "Sign in with ChatGPT is currently available to selected commercial partners through a limited trial" (developers.openai.com/siwc/website).

- Formulário: https://openai.com/form/sign-in-with-chatgpt-interest/
- Robôs recebem 403 nessa página, por isso não consegui ler os campos. Os textos abaixo cobrem o que esse tipo de formulário costuma pedir. Ajuste ao que aparecer.

**Quem envia:** você. É integração externa e autenticação, regra do CLAUDE.md global.

## Dados

| Campo provável | Valor sugerido |
|---|---|
| Empresa | Autonom.ia / Hub2You |
| Produto | Chat2You: plataforma de atendimento multicanal (WhatsApp, Instagram, e-mail, site) com agentes de IA que respondem os clientes de cada empresa |
| Tipo de app | Web app comercial, hospedado (SaaS multi-empresa) |
| Domínios de produção | `chat.hub2you.ai` e `agents.autonomia.site` |
| Redirect URIs | `https://chat.hub2you.ai/openai/callback` e `https://agents.autonomia.site/openai/callback` |
| Redirect de desenvolvimento | `http://localhost:3000/openai/callback`. Perguntar se é aceito; se não for, pedir um client de teste. |
| Tipo de client | Confidencial: o segredo fica só no servidor, e a troca de código e o refresh acontecem no backend |
| Escopos desejados | `openid profile email offline_access resource.invoke chatgpt.tokens.use.direct` (identidade + uso do plano) |
| Contato técnico | (seu e-mail) |
| Volume estimado | (preencher: número de empresas ativas e média de mensagens de IA por dia) |

## Texto de caso de uso (EN, para colar)

> Chat2You is a hosted customer-service platform used by small and mid-size businesses in Brazil. Each business connects its own messaging channels (WhatsApp, Instagram, email, web chat) and configures AI agents that answer that business's customers, summarize conversations and draft replies for the human team.
>
> Today each business must bring its own OpenAI API key. Many owners already pay for ChatGPT Plus/Pro/Business and would rather use that plan. We want to offer "Continue with ChatGPT" in our settings so the business owner (an admin of their workspace) can connect their own ChatGPT plan, with an API key as an optional fallback.
>
> How we would use it:
> - The owner signs in once with ChatGPT in our web app (authorization code + PKCE, confidential client, tokens encrypted at rest, server-side refresh).
> - Requests go to `https://api.openai.com/v1/responses` with `store: false` and `stream: true`, following the preview limitations.
> - We show "Using ChatGPT plan", "Manage usage" and the "Usage limit reached" states exactly as in your UI/UX guidelines. When the plan limit is reached, we stop using the plan and fall back only to the owner's own API key, if they added one. We never fall back to a weaker model silently.
> - One connection belongs to one business workspace and is used only for that business's own work.

## Perguntas para a OpenAI (mandar junto, no campo livre)

São as dúvidas que a doc pública não responde e que mudam o desenho:

1. **Uso sem a pessoa presente.** Os agentes respondem os clientes da empresa 24 horas, sem o dono estar logado no momento da chamada. O uso do plano permite isso, ou exige um usuário ativo em cada requisição?
2. **Uso para atender terceiros.** A conexão é do dono, mas quem conversa com a IA são os clientes dele. Isso é permitido?
3. **Equipe.** Vários atendentes da mesma empresa usando a conexão do dono (rascunhos, resumos). Permitido, ou só o próprio dono?
4. **Planos elegíveis.** Free, Plus, Pro, Business, Enterprise e Edu: quais podem?
5. **Recursos.** No fluxo do plano funcionam `text.format` com `json_schema` (saída estruturada), `reasoning.effort` e `prompt_cache_key`? As páginas não citam esses campos.
6. **Vários domínios.** Um client aceita duas URIs de redirect em domínios diferentes (duas marcas)?
7. **Limites por app.** Existe limite próprio do app além do limite do plano? Como saber o horário em que o limite volta?
8. **Desconexão.** Existe webhook ou evento quando o usuário revoga o acesso pelo ChatGPT?
9. **Dados.** As requisições feitas pelo app com o plano do usuário ficam retidas, aparecem no histórico do ChatGPT ou entram em treino? Seguem os controles de dados da conta ("Improve the model for everyone") ou a política de dados da API? As mensagens podem ter dado pessoal dos clientes da empresa (CPF, saúde).

## O que eu faço enquanto o pedido está em análise

- Deixo o login ChatGPT **pronto e desligado**. Ele só aparece quando existir o `client_id` cadastrado na configuração da plataforma.
- Entrego antes o que vale sem a OpenAI:
  - chave cifrada;
  - aviso de "crédito acabou";
  - teste de chave que pega conta sem crédito;
  - a camada que deixa ligar o login sem mexer nas funcionalidades.
- Se a resposta for "não pode uso sem a pessoa presente", o login fica só para o que o dono faz na hora (rascunho, resumo, Construtor). Os agentes 24 horas continuam na chave.

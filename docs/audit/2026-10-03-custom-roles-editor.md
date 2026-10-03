# 2026-10-03 — Funções personalizadas: novo editor (PR 1, só front)

## Contexto
Rodrigo pediu a tela de funções personalizadas mais simples e com cara de produto.
Mockup aprovado por ele em 03/10, em três rodadas (fidelidade ao produto, seletor
alinhado, jornada em passos e tela de perfil em lista + painel).

## Decisões
- Modal trocado por página: `settings/custom-roles/new` e `settings/custom-roles/:roleId/edit`.
- Criar função em dois passos: escolher perfil (8 perfis + começar do zero) e ajustar só o que muda.
- Áreas em grupos recolhíveis com resumo de uma linha; seletor de nível com três posições fixas.
- Ajustes finos sensíveis (`crm_manage_ai`, `crm_export`, `crm_admin`) pedem confirmação.
- `crm_admin` ligado liga também as outras chaves de CRM, porque o backend já trata assim.
- Prospecção em Editar sugere Campanhas em Editar (enviar leads exige `campaign_manage`).
- Depois de criar, oferece atribuir a função a agentes (só agentes, nunca administradores).
- Lista em cartões com agentes por função e duplicar.
- Sem chave nova nem mudança de backend. As permissões novas da proposta ficam para os PRs 2 a 4.
- Botões que dependiam de `isAdmin` passam a respeitar a chave que o backend já aceita:
  criar etiqueta pela conversa (`label_manage`) e importar lista de campanha (`campaign_manage`).
- Idioma "Português (pt)": o arquivo da tela estava desatualizado e mostrava "Please enter a name."
  na conta do Rodrigo. Passa a espelhar o pt_BR nesta tela.

## Validação
- Vitest das funções personalizadas e do store: 48 testes, 0 falhas.
- Suíte de front inteira: 7427 passando, 19 falhando em 6 arquivos de data/fuso horário
  (Mac em -03, testes esperam UTC). Os mesmos 6 arquivos com `TZ=UTC`: 186 de 186.
- ESLint nos arquivos tocados: 0 erros.
- Compilação das SFCs com `@vue/compiler-sfc`: 0 erros.
- Chaves de tradução usadas: 237, nenhuma faltando em en, pt_BR e pt.
- Não validado: tela rodando no app. Sem ambiente local de Rails nesta sessão.

## Revisão independente
Revisor (agente) apontou dois pontos, ambos corrigidos com teste:
- O `SettingsWrapper` guardava a página em cache por caminho. Abrir "Nova função" de novo,
  ou reabrir uma função depois de cancelar, mostraria dados antigos. As rotas de funções
  agora passam `keepAlive: false`.
- Com "Acesso total ao CRM" ligado, dava para desligar opções que o backend continua
  liberando por `crm_admin`. Essas opções ficam travadas e explicam por quê.

Depois das correções: 51 testes das funções personalizadas e do store, 0 falhas.

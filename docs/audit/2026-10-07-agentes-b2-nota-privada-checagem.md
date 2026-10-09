# Checagem limitada B2-TEC-01 — nota privada

**Data:** 2026-10-07  
**Alvo:** snapshot23 `/Users/Shared/maccluster-workspaces/chat2you/20261007-184308-532a5b7b-9803329751-205ae53c/src`  
**SHA:** `9803329751ae3fce6fd8cec442e77faa9170b38434587aac62a8e81438e480ad`

Esta checagem foi somente leitura e ficou restrita à correção do achado B2-TEC-01.
Não houve execução de RSpec, JavaScript, build, banco, serviço ou produção.

## Causa já registrada e correção conferida

O RED22 havia provado três atravessamentos da mesma causa: POST criava report para
nota privada, Analytics contava uma resposta errada e o drawer devolvia uma linha;
o RED JavaScript também mostrou `reportAgent=true` no menu privado. No snapshot23:

- `MessageReportsController` rejeita `private?` antes da criação e preserva o
  `422`/erro contratual;
- `Analytics#wrong_reply_reports` exige `messages.private: false`, excluindo
  também reports históricos;
- o drawer Enterprise consome essa relação filtrada e não tem caminho paralelo;
- `Message.vue` exige `!props.private` para oferecer `reportAgent`.

As specs novas cobrem entrada, métrica, drawer e menu, além de preservar a resposta
pública do espelho quando o agente ficou silencioso.

## Resultado da checagem

**PASS limitado no código congelado; nenhum residual concreto encontrado.** A
execução test23 permanecia pendente e não foi tratada como GREEN ou aprovação de
release.


# #436 — fechamento local de UI e locales

Data: 2026-09-16. Resultado: correção dos imports de `zh` e validação frontend focada concluídas; navegador e integração backend permanecem com o parent. Não é declaração de PR pronto ou de aprovação visual/produção.

## Escopo e decisão

Lidos `AGENTS.md`, `436-i18n-visible.md`, `436-ui.md` e `436-visual.md`. A autorização desta rodada permite corrigir os imports ausentes, mantendo escrita limitada aos quatro caminhos designados. Foram alterados apenas:

- `app/javascript/dashboard/i18n/locale/zh/index.js`;
- `app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js`;
- este documento.

`scripts/check-email-protection-i18n.mjs` foi executado e permaneceu inalterado: já resolve caminhos relativos reais, verifica montagem dos namespaces, compilação, tokens e renderização sem fallback. Nenhum teste existente foi removido, ignorado ou enfraquecido.

O índice de `zh` tinha 39 imports: 18 locais existentes e 21 ausentes. Todos os equivalentes de mesmo nome existem em `zh_CN`. Foram conferidos os JSONs, suas raízes e amostras de texto: por exemplo, `过滤会话`, `自定义属性`, `审计日志`, `团队` e `请选择想要发送的 Whatsapp 消息模板` usam chinês simplificado, compatível com o `zh` existente (`管理员`, `电子邮件`, `服务器`). Nenhuma raiz desses 21 recursos se sobrepõe às raízes dos 18 recursos locais já importados.

De/para aplicado somente aos 21 caminhos inexistentes: `./<nome>.json` → `../zh_CN/<nome>.json`. Nomes: `advancedFilters`, `agentBots`, `attributesMgmt`, `auditLogs`, `automation`, `bulkActions`, `components`, `contactFilters`, `csatMgmt`, `customRole`, `datePicker`, `emoji`, `general`, `helpCenter`, `inbox`, `integrationApps`, `macros`, `search`, `sla`, `teamsSettings`, `whatsappTemplates`.

Os 18 imports locais e o bloco exportado completo, incluindo ordem dos spreads, foram preservados. Os recursos compartilhados são importações explícitas, não fallback de runtime. Não houve cópia de inglês, substituição integral de locale, alteração de JSON ou ativação de idioma. O registro continua com 43 idiomas ativos; `zh` permanece inativo.

Dois testes novos importam o módulo real de `zh`: um compara integralmente cada raiz dos 18 recursos originalmente importados e confirma ausência de `zh` no registro ativo; o outro compara cada raiz dos 21 recursos compartilhados com os JSONs reais de `zh_CN`. Os testes existentes continuam importando os 57 módulos reais e verificando mensagens efetivas, distinções semânticas, interpolação e `fallbackLocale: false`.

## Comandos e resultados

Executados na raiz do worktree, com dependências já presentes.

```sh
node scripts/check-email-protection-i18n.mjs
```

Antes da correção: saída 1, `ENOENT` ao abrir `app/javascript/dashboard/i18n/locale/zh/advancedFilters.json`. Após a correção: saída 0, 57 diretórios, 57 índices carregáveis, 43 locales ativos, nenhum índice ausente. São 92 mensagens de proteção + 167 legadas = 259 por idioma; **14.763 pares idioma/chave compilados e renderizados**, com interpolação conferida e fallback desabilitado. Nenhuma falha.

```sh
node_modules/.bin/vitest run app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs app/javascript/dashboard/api/specs/emailCampaignProtection.spec.js app/javascript/dashboard/composables/spec/useAbortableRequest.spec.js --maxWorkers=2 --minWorkers=1 --no-cache --no-coverage > /tmp/436-ui-closure-vitest.log 2>&1
```

Resultado final: **237 aprovados, zero falhas, zero ignorados; nove arquivos aprovados**, saída 0. Início `19:39:34`, conforme relógio do runner, duração 4,61 s. Distribuição: locales 156; panels 44; recipients 13; useAbortableRequest 9; actions 6; presentation 4; API 3; management 1; campaignList 1. Log em `/tmp/436-ui-closure-vitest.log`. Máximo de dois workers; sem cobertura/cache do Vitest.

A primeira execução usou o mesmo comando, sem redirecionamento, e terminou com 236 aprovados/uma falha, oito arquivos aprovados/um reprovado, saída 1. Falhou somente o teste novo de preservação: ele assumia que todo JSON existente em `zh` era importado. `zh/webhooks.json`, raiz `WEBHOOKS_SETTINGS`, já existia sem import no índice. Corrigida a premissa do teste para os 18 recursos efetivamente importados antes desta rodada, com igualdade integral por raiz. O produto não ganhou import de webhooks; nenhum teste anterior foi reduzido. Nenhuma falha alheia ao escopo foi encontrada na suíte focada.

```sh
node_modules/.bin/eslint app/javascript/dashboard/i18n/locale/zh/index.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js
node_modules/.bin/prettier --write app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js
node_modules/.bin/prettier --check app/javascript/dashboard/i18n/locale/zh/index.js app/javascript/dashboard/components-next/Campaigns/EmailProtection/specs/locales.spec.js docs/audit/436-ui-closure.md
```

ESLint final: saída 0, zero erros/avisos nos dois arquivos alterados de código. A primeira passagem apontou sete erros no teste novo: três de formatação, dois `no-restricted-syntax`, dois `no-await-in-loop`. Substituídos os loops por `Promise.all` e iterações de array; aplicada formatação somente ao spec. O Prettier inicial dos dois arquivos encontrou um arquivo fora do padrão. Prettier final dos três arquivos alterados: saída 0, todos aprovados. Não foram adicionadas supressões de lint.

Comparação adicional executada contra a leitura inicial desta sessão:

```sh
python3 - <<'PY'
from pathlib import Path
import re,json,hashlib
root=Path('app/javascript/dashboard/i18n/locale'); before=Path('/tmp/436-zh-index-before.js').read_text(); after=(root/'zh/index.js').read_text()
imports=lambda s: re.findall(r"import (\w+) from '([^']+)';",s)
old,new=imports(before),imports(after)
assert len(old)==len(new)==39
changes=[]
for (name,src),(new_name,dst) in zip(old,new):
 assert name==new_name
 if (root/'zh'/src).exists(): assert dst==src
 else:
  assert dst=='../zh_CN/'+Path(src).name
  changes.append(src)
assert len(changes)==21
assert before[before.index('export default'):]==after[after.index('export default'):]
hashes=json.loads(Path('/tmp/436-closure-locales-before.json').read_text())
changed=[p for p,h in hashes.items() if hashlib.sha256(Path(p).read_bytes()).hexdigest()!=h]
assert changed==[str(root/'zh/index.js')],changed
assert set(hashes)=={str(p) for p in root.rglob('*') if p.is_file()}
print(json.dumps({'imports':39,'changed_missing_paths':21,'retained_local_imports':18,'export_unchanged':True,'locale_files_checked':len(hashes),'changed_locale_files':changed},indent=2))
PY
```

Saída 0: 2.829 arquivos de locale conferidos por SHA-256; somente `zh/index.js` mudou, sem arquivos adicionados/removidos nesse diretório. A cópia do índice e o inventário de hashes em `/tmp` foram produzidos antes da edição, a partir dos arquivos locais, sem Git.

## Limites e encaminhamento

- Não houve revisão por falantes nativos. Amostras comprovam a variante escrita selecionada; não certificam qualidade linguística integral. Os recursos existentes de `zh_CN` também contêm textos ingleses preexistentes fora do corpus de e-mail. Foram preservados, sem ampliar esta tarefa para traduzir outros produtos.
- O checker cobre as 259 mensagens selecionadas por idioma, não todas as mensagens de todos os produtos. Os novos testes de recursos verificam preservação integral dos objetos, sem afirmar revisão linguística de cada frase.
- Vitest emitiu aviso de Browserslist/caniuse-lite desatualizado. Nenhuma dependência foi instalada ou atualizada.
- Não houve build, servidor, navegador, screenshot novo, Rails, banco, SSH, AWS, SMTP, leitura de credenciais/configuração de ambiente, mudança de segurança ou operação Git de escrita. Testes usam módulos reais e dados sintéticos/mocks; não provam backend E2E.
- A evidência visual anterior de 87 passes/5 falhas é histórica. A nova execução de navegador, especialmente árabe/alemão/português/mobile, e o aceite das correções visuais pertencem ao parent. Não se afirma que as capturas anteriores foram substituídas ou aprovadas por esta rodada.
- Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback permanece sob condução do parent. Esta entrega resolve o bloqueio local dos imports e entrega resultados de testes; não autoriza merge/deploy nem declara PR pronto.

## Revisão semântica independente

Os 57 módulos e 259 mensagens por locale foram revisados por modelo. Um achado de plural fixo na validação com contagem variável foi corrigido em it, ro, cs, el, he, lv e bg usando rótulo seguido da contagem, preservando `{key}`/`{count}`. Não houve revisão/certificação humana nativa de todas as traduções. O relatório está em `tmp/email436/i18n-semantic-review.md`; o integrador reexecutará a renderização sem fallback após o wiring final.

## Inspeção visual final do integrador

Os 125 checks de navegador passaram, mas a inspeção da captura mobile identificou a busca encolhida pela largura mínima do seletor ao lado. O formulário foi corrigido para busca e seletor em linhas completas no mobile, mantendo distribuição flexível em desktop. Foi acrescentado um gate de navegador que exige busca de pelo menos220px e rótulo com no máximo duas linhas. O teste não foi reduzido nem a viewport ampliada para ocultar o problema. Alias dos motivos reais de API e valid→análise concluída foram alinhados sem criar promessas de existência da caixa.

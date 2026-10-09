# F2+F3 — bloco completo de criação, Issue #1138

Rodrigo aprovou visualmente o bloco da lista em 08/10 e autorizou a implementação local da jornada inteira. Essa aprovação não valida produção, CI, merge ou deploy. A worktree e a branch existentes serão preservadas; PR #1115 permanece congelado.

## Contratos e responsabilidades

- B3: criar o rascunho E1 antes de responder à abertura com 202; entrevista com `knows` e `suggested_links` estruturados pelo modelo; fechamento após as quatro respostas sem quinta pergunta; publicação atômica com instrução verificada antes do teste válido. BE-05 já existe. Desenho detalhado em B3.md; responsabilidade de r9_tecnica.
- BE-02: listar fontes prontas e aceitas de conhecimento, de outro agente vivo da própria conta, excluindo sistema e FAQ sintética. GET `reusable` retorna `payload`; POST `copy` aceita `source_id` inteiro positivo, aplica o teto de 30 sob lock do agente, cria fonte pendente, anexa a mesma blob e registra `copied_from_source_id`. O parecer não é copiado: `IngestJob` confere o material no novo negócio. Origem inelegível ou alheia retorna 404; formato inválido retorna 422 `invalid_source_id`. Autorização comum da API, sem mudança no create existente. Responsabilidade do root.
- B4b: os campos de apresentação têm efeito real; Testar segue o atendimento e protege ferramentas que escrevem quando o usuário só consulta. Preservar os bytes dos prompts nas variantes sem mudança prevista no PRD. Implementação local, mantendo o futuro PR B4b isolado. Responsabilidade de registrar_decisoes.
- Frontend: uma página nova com Escolha, Conte, Teste, Ligue e Pronto; kit F0, traduções en/pt_BR, sem decisões técnicas sobre modo ou base. Responsabilidade de r9_produto.
- Root: entradas por flag, rotas, métodos de API, Guia, snapshots, testes integrados e prévia.

## Estado e invariantes

Escolha não escreve. Continuar cria thread e rascunho antes de abrir Conte. Sair preserva o estado no servidor. Conte retoma a última thread, sem criar outra; `knows` vem da API, nunca de inferência do frontend sobre a mensagem. O fechamento gera a instrução, ocultada na API, e segue para Teste.

Uma resposta concluída por quem edita, sobre o digest e a sessão atuais, leva a E4. Editar a apresentação limpa a conversa e invalida o teste. Ligue usa canal livre existente, ou nenhum canal no ajudante; publicação transacional, sem ativação parcial quando a associação falha. Deixar desligado permanece E4. Pronto só aparece após sucesso da API.

A flag desligada preserva o legado com a mesma conta, agente e thread. Nenhum guard é ampliado. Instrução e scaffold nunca aparecem no JSON guiado. Agentes de cliente, Cotação e Guia não são alvos de escrita de teste. Arquivados ficam fora das projeções e da reutilização. API, Guia, create e PATCH continuam sem exigir teste (D23); o publish novo exige.

WhatsApp é conectado exclusivamente em Canais/Caixas de entrada. Agentes não ganha QR, tokens nem endpoint de conexão.

## Evidência local planejada

RED combinado das dependências antes do produto. Depois: Ruby e Vitest, lint, i18n, Guia, formatos e build pertinentes. A prévia Rails e Vite usará dados fictícios isolados e provider local explicitamente simulado, sem despesa nem chamada de rede para IA. Fluxo positivo usa API, transações e jobs reais; cenários negativos identificam a simulação de transporte. Isso não valida a qualidade do modelo do fornecedor.

Jornadas: externos sem e com material; salvar e retomar; mudar apresentação e testar de novo; canal único, ocupado ou ausente; erro na construção, teste e publicação; ajudante quando habilitado; conta alheia, perfis e flag desligada. Capturas originais em 1440/400, claro/escuro, conferência visual e de acessibilidade, prévia por HTTP.

Uma revisão normal independente e checagem limitada após correções. Se a checagem exigir novas correções, registrar causa raiz antes de uma final limitada. Erro residual final exige parar e retornar, sem outro ciclo.

## Release continua bloqueado

Backend e frontend terão PRs próprios quando estiverem prontos e revisados. CI no último SHA e planos de validação/volta ainda serão necessários. Novas leituras Q13/Q15 exigem OK específico, sem inferência a partir do OK local. Nenhuma migration prevista. PR #1115 congelado; sem fila, merge ou deploy nesta autorização.

# Links e QR codes — proposta visual

Issue #823. Mock navegável, sem integração com API, sem persistência e sem disparos.

Abrir `index.html` com os demais arquivos na mesma pasta ou servir esta pasta por HTTP. O botão de tema alterna claro/escuro. A navegação contextual está representada; os demais itens são referências visuais.

## Decisões

- Subpágina depois de Campanhas de e-mail e antes de Modelos WhatsApp.
- Gestão de campanhas mantém seu propósito de acompanhamento de e-mail; a proposta retira dela a criação de links.
- Lista com números alinhados, seleção de origem e painel de compartilhamento.
- Criação em diálogo com nome, WhatsApp de destino, mensagem opcional e prévia imediata.
- Tema escuro completo, QR preto sobre branco em ambos os temas.
- Sem métricas de receita, funil ou separação de acessos por QR/link: não estão no contrato consultado.

O backend consultado disponibiliza nome, caixa de entrada, texto pré-preenchido, URL curta, cliques e conversas. Só há listagem, criação e exclusão; não se propõe edição ou pausa nesta entrega. Visualizar material é uma proposta de apresentação; download deste mock entrega o QR demonstrativo SVG. Todos os QRs usam example.invalid, inclusive os de campanhas criadas em memória.

## Referências

Capturas fornecidas pelo Rodrigo, página EmailCampaignsPage.vue, CrmCampaignManagementPage.vue, contrato CtwaTrackedLinksController e chat Campanhas. Identidade extraída dos assets do próprio produto. Skill UI/UX Pro Max: padrões minimalistas para operação, foco visível, rótulos de formulário e contraste nos dois temas. A recomendação inicial de landing/glass foi descartada por não corresponder a esta página.

## Próxima etapa após aceite visual

Implementar rota e menu, extrair a seção atual para a página própria, reutilizar a API e o sistema de componentes e temas existente; atualizar o Guia por geração. Validar tela real antes de merge/deploy. Este mock não prova integração funcional nem publicação.

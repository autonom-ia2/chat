import AxeBuilder from '@axe-core/playwright';
import { expect, type Page } from '@playwright/test';

export async function expectNoSeriousA11y(page: Page) {
  // Existing Guide sidebar controls are outside the Agents redesign. Their
  // known contrast issue (3.77:1) is recorded in the F2/F3 audit; do not
  // exclude any control from the new Agents screens.
  const results = await new AxeBuilder({ page })
    .exclude('[data-guia-abrir]')
    .exclude('[data-guia-entendi]')
    .analyze();
  const blockingViolations = results.violations.filter(violation =>
    ['serious', 'critical'].includes(violation.impact || '')
  );

  expect(
    blockingViolations,
    'A tela real não pode ter violações de acessibilidade serious/critical'
  ).toEqual([]);
}

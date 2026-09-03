import { readFileSync } from 'node:fs';
import { describe, expect, it } from 'vitest';
import insurance from 'dashboard/i18n/locale/en/insurance.json';
import { CONNECTION_STATES, STATE_TONE } from './insuranceContract';

// Os estados da conexão vivem em três lugares: o model Ruby (fonte da verdade), o contrato do
// frontend e os textos. Um estado novo só no backend chega na tela como chave crua — foi o que
// aconteceu com `auth_required` em 03/09/2026. Este teste falha se os três divergirem.
const RUBY_MODEL = 'app/models/autonomia/insurance/connection.rb';

const backendStates = () => {
  const source = readFileSync(RUBY_MODEL, 'utf8');
  const match = /STATUSES\s*=\s*%w\[([^\]]+)\]/.exec(source);
  if (!match) throw new Error(`STATUSES não encontrado em ${RUBY_MODEL}`);
  return match[1].trim().split(/\s+/);
};

describe('estados da conexão (backend x contrato x textos)', () => {
  const states = backendStates();

  it('o contrato do frontend cobre exatamente os estados do model', () => {
    expect([...Object.values(CONNECTION_STATES)].sort()).toEqual(
      [...states].sort()
    );
  });

  it.each(states)('%s tem tom visual definido', state => {
    expect(STATE_TONE[state]).toBeTruthy();
  });

  it.each(states)('%s tem texto traduzido', state => {
    expect(
      insurance.INSURANCE.CONNECTION.STATES[state.toUpperCase()]
    ).toBeTruthy();
  });
});

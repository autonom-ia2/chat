import { describe, it, expect } from 'vitest';
import {
  CONNECTION_STATES,
  FAILURE_CAUSES,
  LAYER_ORDER,
  LAYER_STATES,
  STATE_TONE,
  buildConnection,
  failureMessageKey,
  isConnectedState,
  isTransientState,
  layerRows,
  maskUsername,
} from './insuranceContract';

// AS DUAS ALLOWLISTS QUE FILTRAM O DADO CRU DO ADAPTER.
//
// O Rails grava `failure` e `layers` como vêm (`connections/sync.rb`; `sanitize_deep` limpa texto,
// não valida domínio). Sem estas guardas, um valor novo do lado de lá virava
// `INSURANCE.CONNECTION.FAILURES.QUOTA_EXCEEDED` na tela, ou um estado de camada sem cor nenhuma.
//
// Elas existiam e NÃO TINHAM TESTE: um QA independente removeu as duas e a suíte ficou verde.
// Guarda sem teste é a mesma lista escrita à mão que ela veio substituir.
describe('insuranceContract — o que chega cru do adapter', () => {
  it('causa desconhecida vira o texto generico, e nunca chave crua', () => {
    expect(failureMessageKey({ cause: 'credential_rejected' })).toBe(
      'INSURANCE.CONNECTION.FAILURES.CREDENTIAL_REJECTED'
    );
    ['quota_exceeded', 'QUOTA_EXCEEDED', '', null, undefined, 42].forEach(
      cause => {
        expect(failureMessageKey({ cause })).toBe(
          'INSURANCE.CONNECTION.FAILURES.UNKNOWN'
        );
      }
    );
    expect(failureMessageKey(null)).toBe(
      'INSURANCE.CONNECTION.FAILURES.UNKNOWN'
    );
  });

  // A allowlist é derivada de `FAILURE_CAUSES`, e não uma segunda cópia: toda causa cadastrada
  // precisa ter chave própria, senão a lista e o texto divergem sem ninguém ver.
  it('toda causa cadastrada tem chave propria', () => {
    Object.values(FAILURE_CAUSES).forEach(cause => {
      expect(failureMessageKey({ cause })).toBe(
        `INSURANCE.CONNECTION.FAILURES.${cause.toUpperCase()}`
      );
    });
  });

  it('estado de camada desconhecido vira "unknown", e nunca chave crua', () => {
    LAYER_STATES.forEach(state => {
      expect(layerRows({ runtime: state })[0].state).toBe(state);
    });
    ['skipped', 'OK', 'partial', '', null, 7, {}].forEach(state => {
      expect(layerRows({ runtime: state })[0].state).toBe('unknown');
    });
  });

  it('camada ausente e payload vazio respondem "unknown" para todas', () => {
    [undefined, null, {}].forEach(layers => {
      const rows = layerRows(layers);
      expect(rows).toHaveLength(LAYER_ORDER.length);
      rows.forEach(row => expect(row.state).toBe('unknown'));
    });
  });
});

describe('insuranceContract', () => {
  it('maps every connection state to a visual tone', () => {
    Object.values(CONNECTION_STATES).forEach(state => {
      expect(STATE_TONE[state]).toBeTruthy();
    });
  });

  it('treats only provisioning/authenticating/discovering as transient', () => {
    expect(isTransientState(CONNECTION_STATES.PROVISIONING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.AUTHENTICATING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.DISCOVERING)).toBe(true);
    expect(isTransientState(CONNECTION_STATES.READY)).toBe(false);
    expect(isTransientState(CONNECTION_STATES.HUMAN_REQUIRED)).toBe(false);
  });

  it('treats ready and degraded as connected, never human_required or offline', () => {
    expect(isConnectedState(CONNECTION_STATES.READY)).toBe(true);
    expect(isConnectedState(CONNECTION_STATES.DEGRADED)).toBe(true);
    expect(isConnectedState(CONNECTION_STATES.HUMAN_REQUIRED)).toBe(false);
    expect(isConnectedState(CONNECTION_STATES.OFFLINE)).toBe(false);
  });

  it('masks the username keeping only two leading characters and the domain', () => {
    expect(maskUsername('corretora@exemplo.com.br')).toBe(
      'co*******@exemplo.com.br'
    );
    expect(maskUsername('ab')).toBe('ab**');
    expect(maskUsername('')).toBe('');
  });

  it('builds a not_configured connection without any credential field', () => {
    const connection = buildConnection();
    expect(connection.status).toBe(CONNECTION_STATES.NOT_CONFIGURED);
    expect(connection.capabilities).toEqual([]);
    expect(Object.keys(connection)).not.toContain('password');
    expect(Object.keys(connection)).not.toContain('username');
  });
});

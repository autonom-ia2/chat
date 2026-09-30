import { deleteDB } from 'idb';
import { DataManager } from './DataManager';

const ACCOUNT_ID = 'qa792-cache-snapshots';

describe('DataManager snapshot transactions', () => {
  let first;
  let second;

  beforeEach(async () => {
    await deleteDB(`cw-store-${ACCOUNT_ID}`);
    first = new DataManager(ACCOUNT_ID);
    second = new DataManager(ACCOUNT_ID);
    await Promise.all([first.initDb(), second.initDb()]);
  });

  afterEach(async () => {
    first.db.close();
    second.db.close();
    await deleteDB(`cw-store-${ACCOUNT_ID}`);
  });

  it('serializes concurrent replacements from independent clients without duplicate-key errors', async () => {
    const oldSnapshot = [{ id: 1, name: 'First snapshot' }];
    const newSnapshot = [
      { id: 1, name: 'Second snapshot' },
      { id: 2, name: 'Second only' },
    ];
    const outcomes = await Promise.allSettled([
      first.replace({ modelName: 'inbox', data: oldSnapshot }),
      second.replace({ modelName: 'inbox', data: newSnapshot }),
    ]);
    expect(outcomes.map(item => item.status)).toEqual([
      'fulfilled',
      'fulfilled',
    ]);
    expect(await first.get({ modelName: 'inbox' })).toEqual(newSnapshot);
  });

  it('rolls back the clear and all inserted rows if a replacement has duplicate identities', async () => {
    const original = [{ id: 7, name: 'Keep committed snapshot' }];
    await first.replace({ modelName: 'inbox', data: original });
    await expect(
      first.replace({ modelName: 'inbox', data: [{ id: 1 }, { id: 1 }] })
    ).rejects.toBeDefined();
    expect(await first.get({ modelName: 'inbox' })).toEqual(original);
  });

  it('clears old rows on an empty replacement without clearing another model', async () => {
    await first.replace({ modelName: 'inbox', data: [{ id: 1 }] });
    await first.replace({
      modelName: 'label',
      data: [{ id: 1, title: 'Keep label' }],
    });
    await first.replace({ modelName: 'inbox', data: [] });
    expect(await first.get({ modelName: 'inbox' })).toEqual([]);
    expect(await first.get({ modelName: 'label' })).toEqual([
      { id: 1, title: 'Keep label' },
    ]);
  });

  it('keeps append semantics for arrays and single records', async () => {
    await first.push({ modelName: 'inbox', data: { id: 1 } });
    await first.push({ modelName: 'inbox', data: [{ id: 2 }] });
    expect(await first.get({ modelName: 'inbox' })).toEqual([
      { id: 1 },
      { id: 2 },
    ]);
  });

  it('rejects a conflicting append without overwriting the stored item', async () => {
    await first.push({
      modelName: 'inbox',
      data: [{ id: 1, name: 'Original' }],
    });
    await expect(
      second.push({ modelName: 'inbox', data: [{ id: 1, name: 'Other' }] })
    ).rejects.toBeDefined();
    expect(await first.get({ modelName: 'inbox' })).toEqual([
      { id: 1, name: 'Original' },
    ]);
  });

  it('still rejects unsupported model names before opening a transaction', async () => {
    await expect(
      first.replace({ modelName: 'unavailable', data: [] })
    ).rejects.toThrow('not defined');
  });
});

import fs from 'node:fs';

const file = process.argv[2];
if (!file) {
  console.error('usage: node report-settings.mjs <settings.json>');
  process.exit(2);
}

const root = JSON.parse(fs.readFileSync(file, 'utf8'));
const imports = root.Imports ?? [];
const name = (idx) => {
  if (idx >= 0) return `export#${idx}`;
  const i = -idx - 1;
  const imp = imports[i];
  return imp ? String(imp.ObjectName) : `import#${i}?`;
};

const data = root.Exports[0].Data;
const diff = data
  .filter((p) => p.Name === 'DifficultySettingsArray')
  .sort((a, b) => a.ArrayIndex - b.ArrayIndex);

console.log(`difficulties=${diff.length}`);
for (const d of diff) {
  console.log(`=== difficulty ${d.ArrayIndex} ===`);
  const props = d.Value;
  for (const key of ['MaxNumPawnsAlive', 'MaxNumSquadsAlive', 'MaxNumSquadsPerWave', 'MaxNumPawnsPerPlayer', 'SquadCooldown']) {
    const p = props.find((x) => x.Name === key);
    if (p) console.log(`  ${key}=${JSON.stringify(p.Value)}`);
  }
  const prog = props.find((x) => x.Name === 'ProgressionArray');
  if (!prog) continue;
  for (const t of prog.Value) {
    const start = t.Value.find((x) => x.Name === 'StartAtProgression');
    console.log(`  tier start=${start ? start.Value : '?'}`);
    const squads = t.Value.find((x) => x.Name === 'SquadArray');
    if (!squads) continue;
    for (const s of squads.Value) {
      const w = s.Value.find((x) => x.Name === 'Weight');
      const pawns = s.Value.find((x) => x.Name === 'PawnArray');
      const pawnNames = pawns ? pawns.Value.map((o) => name(o.Value)).join(' + ') : '?';
      console.log(`    w=${w ? w.Value : '?'}  ${pawnNames}`);
    }
  }
}

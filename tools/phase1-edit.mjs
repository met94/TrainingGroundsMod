import fs from 'node:fs';

const [, , inFile, outFile] = process.argv;
if (!inFile || !outFile) {
  console.error('usage: node phase1-edit.mjs <in.json> <out.json>');
  process.exit(2);
}

const root = JSON.parse(fs.readFileSync(inFile, 'utf8'));
const data = root.Exports[0].Data;

const marker = data.find((p) => p.Name === 'MaxTotalAISpawnCount');
if (!marker) throw new Error('MaxTotalAISpawnCount not found');
marker.Value = 213;

const diff0 = data
  .filter((p) => p.Name === 'DifficultySettingsArray')
  .find((p) => p.ArrayIndex === 0);
const tier0 = diff0.Value.find((p) => p.Name === 'ProgressionArray').Value[0];
const squads = tier0.Value.find((p) => p.Name === 'SquadArray').Value;

const dozerImport = -9; // import index 8 = /Game/Gameplay/AI/Assault/DA_Special_Dozer
const template = squads[0].Value.find((p) => p.Name === 'PawnArray').Value[0];
const first = squads[0];
first.Value.find((p) => p.Name === 'PawnArray').Value = [{ ...template, Value: dozerImport }];
first.Value.find((p) => p.Name === 'Weight').Value = 1.0;
for (const s of squads.slice(1)) {
  const w = s.Value.find((p) => p.Name === 'Weight');
  if (w) w.Value = 0.0;
}

fs.writeFileSync(outFile, JSON.stringify(root, null, 2));
console.log(`wrote ${outFile}`);
console.log(`marker MaxTotalAISpawnCount=213; tier0 squads=${squads.length}; first=DA_Special_Dozer w=1.0; rest w=0`);

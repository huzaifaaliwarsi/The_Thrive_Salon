// Reconstruct typed columns from the supplied PostgreSQL backup, without connecting to a database.
const fs = require('fs');
const path = require('path');
const dump = fs.readFileSync(path.join(__dirname, '../../Structure & Data.sql'), 'utf8');
const camel = s => s.replace(/_([a-z])/g, (_, c) => c.toUpperCase());
let out = "import { pgTable, pgEnum, uuid, text, numeric, integer, boolean, date, timestamp } from 'drizzle-orm/pg-core';\nimport { relations, sql } from 'drizzle-orm';\n\n";
for (const [, name, values] of dump.matchAll(/CREATE TYPE public\.(\w+) AS ENUM \(([\s\S]*?)\);/g)) {
  out += `export const ${camel(name)} = pgEnum('${name}', [${values.trim()}]);\n`;
}
const tables = [...dump.matchAll(/CREATE TABLE public\.(\w+) \(([\s\S]*?)\n\);/g)];
for (const [, table, body] of tables) {
  out += `\nexport const ${camel(table)} = pgTable('${table}', {\n`;
  for (const line of body.trim().split(/\r?\n/)) {
    const [, col, definition] = line.trim().replace(/,$/, '').match(/^(\w+) (.*)$/);
    let expr;
    if (definition.startsWith('public.')) expr = `${camel(definition.match(/^public\.(\w+)/)[1])}('${col}')`;
    else if (definition.startsWith('timestamp')) expr = `timestamp('${col}')`;
    else if (definition.startsWith('numeric')) {
      const dims = definition.match(/^numeric\((\d+),(\d+)\)/);
      expr = `numeric('${col}'${dims ? `, { precision: ${dims[1]}, scale: ${dims[2]} }` : ''})`;
    } else expr = `${definition.split(' ')[0]}('${col}')`;
    if (col === 'id' && definition.startsWith('uuid')) expr += '.defaultRandom().primaryKey()';
    else if (table === '_sys_config' && col === 'key') expr += '.primaryKey()';
    if (definition.includes('NOT NULL') && col !== 'id') expr += '.notNull()';
    const def = definition.match(/ DEFAULT (.*?)(?: NOT NULL)?$/);
    if (def) expr += '.default(sql`' + def[1] + '`)';
    out += `  ${camel(col)}: ${expr},\n`;
  }
  out += '});\n';
}
// Relation names mirror the existing API's relational queries.
const edges = [...dump.matchAll(/ALTER TABLE ONLY public\.(\w+)\s+ADD CONSTRAINT \w+ FOREIGN KEY \((\w+)\) REFERENCES public\.(\w+)\((\w+)\)/g)];
for (const [, table] of tables) {
  const entries = [];
  for (const [, from, col, to, ref] of edges) {
    const relationName = `${from}_${col}`;
    if (from === table) {
      const name = col === 'noted_by' ? 'notedByUser' : col === 'locked_by' ? 'lockedByUser' : camel(col.replace(/_id$/, ''));
      entries.push(`  ${name}: one(${camel(to)}, { fields: [${camel(from)}.${camel(col)}], references: [${camel(to)}.${camel(ref)}], relationName: '${relationName}' })`);
    }
    if (to === table) {
      let name = camel(from);
      if (from === 'service_package_items') name = col === 'package_id' ? 'bundleItems' : 'packageMemberships';
      entries.push(`  ${name}: many(${camel(from)}, { relationName: '${relationName}' })`);
    }
  }
  if (entries.length) out += `\nexport const ${camel(table)}Relations = relations(${camel(table)}, ({ one, many }) => ({\n${entries.join(',\n')}\n}));\n`;
}
fs.writeFileSync(path.join(__dirname, '../src/db/schema.ts'), out);
console.log(`Recovered ${tables.length} tables and ${edges.length} relations.`);

const { app, BrowserWindow, ipcMain, shell } = require('electron');
const path = require('path');

const UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/128 Safari/537.36';
const cache = new Map();
app.setName('Mayhem Pocket');
if (process.platform === 'win32') app.setAppUserModelId('com.mayhempocket.windows');

async function text(url, fresh = false) {
  const hit = cache.get(url);
  if (!fresh && hit && Date.now() - hit.time < 10 * 60_000) return hit.value;
  const response = await fetch(url, { headers: { 'user-agent': UA, 'accept-language': 'en-US,en;q=0.9' }, cache: fresh ? 'no-store' : 'default' });
  if (!response.ok) throw new Error(`OP.GG returned ${response.status}`);
  const value = await response.text();
  cache.set(url, { time: Date.now(), value });
  return value;
}

const clean = value => value
  .replace(/\\u003c/gi, '<').replace(/\\u003e/gi, '>').replace(/\\u0026/gi, '&')
  .replace(/<[^>]+>/g, '').replace(/@[^@]+@/g, '').replace(/&amp;/g, '&')
  .replace(/&#x27;|&#39;/g, "'").replace(/&quot;/g, '"');

function decoded(value) {
  try { return JSON.parse(`"${value.replace(/"/g, '\\"')}"`); } catch { return value; }
}

function slug(id) {
  const special = { MonkeyKing:'wukong', KSante:'ksante', Kaisa:'kaisa', Khazix:'khazix', Velkoz:'velkoz', RekSai:'reksai', Belveth:'belveth', Chogath:'chogath' };
  return special[id] || id.toLowerCase();
}

function itemRows(html, prefix, boundary, itemMap, limit) {
  const markers = [...html.matchAll(new RegExp(`"${prefix}_[0-9]+"`, 'g'))];
  return markers.slice(0, limit).map((marker, index) => {
    const start = marker.index + marker[0].length;
    let stop = markers[index + 1]?.index ?? Math.min(start + 18000, html.length);
    if (boundary) { const at = html.indexOf(`"${boundary}_0"`, start); if (at >= 0 && at < stop) stop = at; }
    const ids = [...html.slice(start, stop).matchAll(/"metaId":([0-9]+)/g)].map(x => x[1]);
    return [...new Set(ids)].map(id => itemMap[id]).filter(Boolean);
  }).filter(row => row.length);
}

function parseSpellSets(html) {
  const markers = [...html.matchAll(/"spell_0"/g)], result = [];
  markers.forEach((marker, i) => {
    const section = html.slice(marker.index, markers[i+1]?.index ?? marker.index + 4000);
    const pair = [...section.matchAll(/src":"(https:[^"]+\/spell\/[^"]+)"[^}]+alt":"([^"]+)"/g)]
      .slice(0, 2).map(x => ({ url: x[1], name: decoded(x[2]) }));
    if (pair.length === 2 && !result.some(r => r.map(x=>x.name).join('|') === pair.map(x=>x.name).join('|'))) result.push(pair);
  });
  return result;
}

function parseSkills(html) {
  const at = html.lastIndexOf('SkillOrder Table');
  if (at < 0) return { priority: [], order: [] };
  const section = html.slice(at, at + 16000);
  const priority = [...section.matchAll(/extraData":"([QWE])"/g)].slice(0,3).map(x=>x[1]);
  const levelsAt = section.indexOf('inline-flex flex-wrap gap-0.5');
  const order = levelsAt < 0 ? [] : [...section.slice(levelsAt).matchAll(/children":"([QWER])"/g)].slice(0,15).map(x=>x[1]);
  return { priority, order };
}

function parseAugments(raw) {
  const html = raw.replace(/\\"/g, '"');
  const regex = /\{"id":([0-9]+),"tier":([0-9]+),"performance":([^,]+),"popular":([^,]+),"name":"([^"]+)","key":"[^"]+","largeIcon":"([^"]+)","smallIcon":"[^"]+","rarity":([0-9]+),"desc":"(.*?)","tooltip"/g;
  const seen = new Set(), values = [];
  for (const match of html.matchAll(regex)) {
    if (seen.has(match[1])) continue; seen.add(match[1]);
    const rawRarity = Number(match[7]);
    values.push({ id: match[1], tier: Number(match[2]), performance: Number(match[3]), popular: Number(match[4]),
      name: decoded(match[5]), icon: `${match[6]}?image=q_auto:good,f_png,w_96,h_96`,
      rarity: rawRarity === 8 ? 2 : rawRarity === 4 ? 1 : 0, description: clean(decoded(match[8])) });
  }
  return values;
}

async function champions(fresh = false) {
  const versions = JSON.parse(await text('https://ddragon.leagueoflegends.com/api/versions.json', fresh));
  const patch = versions[0];
  const root = JSON.parse(await text(`https://ddragon.leagueoflegends.com/cdn/${patch}/data/en_US/champion.json`, fresh));
  return { patch, champions: Object.values(root.data).map(c => ({ id:c.id, key:c.key, name:c.name, slug:slug(c.id), icon:`https://ddragon.leagueoflegends.com/cdn/${patch}/img/champion/${c.image.full}` })).sort((a,b)=>a.name.localeCompare(b.name)) };
}

async function build(champion, fresh = false) {
  const listing = await champions(fresh), patch = listing.patch;
  const [buildRaw, augmentRaw, itemsRaw] = await Promise.all([
    text(`https://op.gg/lol/modes/aram-mayhem/${champion.slug}/build`, fresh),
    text(`https://op.gg/lol/modes/aram-mayhem/${champion.slug}/augments`, fresh),
    text(`https://ddragon.leagueoflegends.com/cdn/${patch}/data/en_US/item.json`, fresh)
  ]);
  const buildHtml = buildRaw.replace(/\\"/g, '"'), itemData = JSON.parse(itemsRaw).data, itemMap = {};
  Object.entries(itemData).forEach(([id,x]) => itemMap[id] = { id, name:x.name, price:x.gold.total, icon:`https://ddragon.leagueoflegends.com/cdn/${patch}/img/item/${x.image.full}` });
  const starts = itemRows(buildHtml, 'starter_items', 'boots', itemMap, 3);
  const boots = itemRows(buildHtml, 'boots', 'core_items', itemMap, 3).map(x=>x[0]).filter(Boolean);
  const cores = itemRows(buildHtml, 'core_items', null, itemMap, 5);
  const augments = parseAugments(augmentRaw), skills = parseSkills(buildHtml), spellSets = parseSpellSets(buildHtml);
  if (!starts.length || !cores.length || !augments.length) throw new Error('OP.GG page format changed; no fallback data was displayed.');
  return { patch, fetchedAt:new Date().toLocaleString(), starts, boots, cores, augments, ...skills, spellSets };
}

function createWindow() {
  const win = new BrowserWindow({ width: 900, height: 800, minWidth: 720, minHeight: 600, backgroundColor:'#111827', icon:path.join(__dirname,'assets','app-icon.png'),
    webPreferences: { preload:path.join(__dirname,'preload.js'), contextIsolation:true, nodeIntegration:false } });
  win.removeMenu(); win.loadFile('index.html');
  ipcMain.on('pin', (_e, value) => win.setAlwaysOnTop(Boolean(value)));
}

ipcMain.handle('champions', (_e, fresh) => champions(Boolean(fresh)));
ipcMain.handle('build', (_e, champion, fresh) => build(champion, Boolean(fresh)));
ipcMain.on('open-opgg', (_e, slug) => shell.openExternal(`https://op.gg/lol/modes/aram-mayhem/${slug}/build`));
app.whenReady().then(createWindow);
app.on('window-all-closed', () => app.quit());

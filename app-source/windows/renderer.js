let roster=[], selected=null, current=null, rarity=2, pinned=false;
const $=id=>document.getElementById(id);
const item=x=>`<div class="item"><img src="${x.icon}"><label title="${x.name}">${x.name}</label></div>`;
const sequence=(row,i)=>`<div class="row"><span class="row-number">${i+1}</span>${row.map(item).join('<span class="arrow">›</span>')}</div>`;
const skills=values=>values.map(x=>`<span class="skill ${x==='R'?'r':''}">${x}</span>`).join('');

function showAugments(){
  const labels=['S','A','B','C','D','F'];
  $('augments').innerHTML=current.augments.filter(x=>x.rarity===rarity).map(x=>`<div class="augment"><img src="${x.icon}"><div><strong>${x.name}</strong><p>${x.description}</p></div><span class="grade">${labels[Math.min(x.tier,5)]}</span></div>`).join('');
  document.querySelectorAll('.tabs button').forEach(b=>b.classList.toggle('active',Number(b.dataset.rarity)===rarity));
}
function render(data){current=data;$('patch').textContent=`Patch ${data.patch}`;$('fetched').textContent=`Fetched ${data.fetchedAt}`;
  $('spells').innerHTML=data.spellSets.map(row=>`<div class="row">${row.map(x=>`<div class="spell"><img src="${x.url}"><label>${x.name}</label></div>`).join('')}</div>`).join('');
  $('priority').innerHTML=skills(data.priority);$('skillOrder').innerHTML=skills(data.order);
  $('starts').innerHTML=data.starts.map(sequence).join('');$('boots').innerHTML=data.boots.map(item).join('');$('cores').innerHTML=data.cores.map(sequence).join('');showAugments();
}
async function load(fresh=false){if(!selected)return;$('status').hidden=false;$('status').textContent='Loading current OP.GG recommendations…';$('content').hidden=true;try{render(await window.mayhem.build(selected,fresh));$('status').hidden=true;$('content').hidden=false}catch(e){$('status').innerHTML=`<b>Couldn’t read OP.GG data.</b><br><br>${e.message}<br><br>Press Refresh to try again.`}}
async function init(){try{const result=await window.mayhem.champions(false);roster=result.champions;$('champions').innerHTML=roster.map(x=>`<option value="${x.name}">`).join('');selected=roster.find(x=>x.name==='Aatrox')||roster[0];$('champion').value=selected.name;$('championIcon').src=selected.icon;load()}catch(e){$('status').textContent=e.message}}
$('champion').addEventListener('change',()=>{const c=roster.find(x=>x.name.toLowerCase()===$('champion').value.toLowerCase());if(c){selected=c;$('championIcon').src=c.icon;load()}});
$('refresh').onclick=()=>load(true);$('pin').onclick=()=>{pinned=!pinned;window.mayhem.pin(pinned);$('pin').textContent=pinned?'📌 Pinned':'📌 Pin'};$('opgg').onclick=()=>selected&&window.mayhem.openOPGG(selected.slug);
document.querySelectorAll('.tabs button').forEach(b=>b.onclick=()=>{rarity=Number(b.dataset.rarity);showAugments()});init();

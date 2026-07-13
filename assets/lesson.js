/* Shared behavior for materials/lesson pages. Progress lives in the same
   localStorage key as the tracker (index.html), so ticking a lesson here
   ticks the checkpoint there. */
(function(){
  var KEY='cka-prep-v1', TKEY='cka-theme';
  var state={};
  try{ state=JSON.parse(localStorage.getItem(KEY)||'{}'); }catch(e){ state={}; }

  /* ---- theme ---- */
  var root=document.documentElement;
  var savedTheme=localStorage.getItem(TKEY);
  if(savedTheme) root.dataset.theme=savedTheme;
  var tbtn=document.getElementById('theme');
  if(tbtn) tbtn.addEventListener('click', function(){
    var current=root.dataset.theme ||
      (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    var next=current==='dark' ? 'light' : 'dark';
    root.dataset.theme=next;
    localStorage.setItem(TKEY, next);
  });

  /* ---- beginner-mode toggle (foundations/analogy panels) ---- */
  var BKEY='cka-beginner-v1';
  if(localStorage.getItem(BKEY)==='off') document.body.classList.add('basics-off');
  var bbtn=document.getElementById('basics');
  if(bbtn) bbtn.addEventListener('click', function(){
    var off=document.body.classList.toggle('basics-off');
    localStorage.setItem(BKEY, off? 'off':'on');
  });

  /* ---- mark-done sync ---- */
  var lessons=[].slice.call(document.querySelectorAll('.lesson[data-id]'));

  function paint(){
    lessons.forEach(function(l){
      var on=!!state[l.dataset.id];
      var box=l.querySelector('.donebox input');
      if(box) box.checked=on;
      l.classList.toggle('is-done', on);
    });
    refresh();
  }

  function refresh(){
    var done=lessons.filter(function(l){ return l.classList.contains('is-done'); }).length;
    var pct=document.getElementById('pct'), dc=document.getElementById('done-count'), ring=document.getElementById('ring');
    if(pct) pct.textContent=(lessons.length? Math.round(done/lessons.length*100):0)+'%';
    if(dc) dc.textContent=done+' / '+lessons.length;
    if(ring) ring.style.setProperty('--p', lessons.length? Math.round(done/lessons.length*100):0);
    navCounts();
  }

  lessons.forEach(function(l){
    var box=l.querySelector('.donebox input');
    if(!box) return;
    box.addEventListener('change', function(){
      if(box.checked) state[l.dataset.id]=1; else delete state[l.dataset.id];
      localStorage.setItem(KEY, JSON.stringify(state));
      l.classList.toggle('is-done', box.checked);
      refresh();
    });
  });

  window.addEventListener('storage', function(e){
    if(e.key!==KEY) return;
    try{ state=JSON.parse(e.newValue||'{}'); }catch(err){ state={}; }
    paint();
  });

  /* ---- on-page nav (one entry per .grp) ---- */
  var nav=document.getElementById('nav'), grps=[].slice.call(document.querySelectorAll('.grp[id]'));
  if(nav) grps.forEach(function(g){
    var h=g.querySelector('h3');
    var li=document.createElement('li'), a=document.createElement('a');
    a.href='#'+g.id;
    a.innerHTML='<span>'+(h? h.textContent : g.id)+'</span><span class="count"></span>';
    li.appendChild(a); nav.appendChild(li);
    g._nav=a;
  });
  function navCounts(){
    grps.forEach(function(g){
      if(!g._nav) return;
      var list=[].slice.call(g.querySelectorAll('.lesson[data-id]'));
      var d=list.filter(function(l){ return l.classList.contains('is-done'); }).length;
      g._nav.querySelector('.count').textContent=list.length? d+'/'+list.length : '';
      g._nav.classList.toggle('done-week', d===list.length && list.length>0);
    });
  }

  /* ---- collapse/expand groups (per page, persisted) ---- */
  var GKEY='cka-grp-collapsed-v1', page=(location.pathname.split('/').pop()||'index');
  var collapsed={};
  try{ collapsed=JSON.parse(localStorage.getItem(GKEY)||'{}'); }catch(e){ collapsed={}; }
  function gkey(g){ return page+'#'+g.id; }
  function saveCollapsed(){ localStorage.setItem(GKEY, JSON.stringify(collapsed)); }
  function setCollapsed(g, on){
    g.classList.toggle('is-collapsed', on);
    var t=g.querySelector('.grp-toggle');
    if(t) t.setAttribute('aria-expanded', on? 'false':'true');
    if(on) collapsed[gkey(g)]=1; else delete collapsed[gkey(g)];
  }
  grps.forEach(function(g){
    var h=g.querySelector('h3');
    if(!h) return;
    var body=document.createElement('div');
    body.className='grp-body';
    while(h.nextSibling) body.appendChild(h.nextSibling);
    g.appendChild(body);
    var btn=document.createElement('button');
    btn.className='grp-toggle'; btn.type='button'; btn.setAttribute('aria-expanded','true');
    btn.innerHTML='<span>▾</span>';
    h.insertBefore(btn, h.firstChild);
    setCollapsed(g, !!collapsed[gkey(g)]);
    btn.addEventListener('click', function(){
      setCollapsed(g, !g.classList.contains('is-collapsed'));
      saveCollapsed();
    });
    if(g._nav) g._nav.addEventListener('click', function(){ setCollapsed(g, false); saveCollapsed(); });
  });
  if(nav && grps.length){
    var ctrl=document.createElement('div');
    ctrl.className='sect-controls';
    ctrl.innerHTML='<button type="button" id="expandAll">expand all</button>'+
      '<button type="button" id="collapseAll">collapse all</button>';
    nav.parentNode.parentNode.insertBefore(ctrl, nav.parentNode);
    ctrl.querySelector('#expandAll').addEventListener('click', function(){
      grps.forEach(function(g){ setCollapsed(g, false); }); saveCollapsed();
    });
    ctrl.querySelector('#collapseAll').addEventListener('click', function(){
      grps.forEach(function(g){ setCollapsed(g, true); }); saveCollapsed();
    });
  }

  /* ---- copy buttons on command blocks ---- */
  [].slice.call(document.querySelectorAll('pre.cmd')).forEach(function(pre){
    var text=pre.textContent.replace(/\s+$/,'');
    var b=document.createElement('button');
    b.className='copy-btn'; b.type='button'; b.textContent='copy';
    b.addEventListener('click', function(){
      (navigator.clipboard? navigator.clipboard.writeText(text) : Promise.reject())
        .then(function(){ b.textContent='copied'; setTimeout(function(){ b.textContent='copy'; },1200); })
        .catch(function(){ b.textContent='select & copy'; });
    });
    pre.appendChild(b);
  });

  paint();
})();
